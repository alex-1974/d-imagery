#!/usr/bin/env bash

compiler="${1:-dmd}"

tmp_dir="$(
    mktemp -d \
        "/tmp/imagery-d-raster-writable-view-XXXXXX"
)"

cleanup()
{
    rm -rf "$tmp_dir"
}

trap cleanup EXIT

failures=0


compile_probe()
{
    name="$1"
    expectation="$2"

    source="$tmp_dir/$name.d"
    object="$tmp_dir/$name.o"
    stderr="$tmp_dir/$name.stderr"

    if "$compiler" \
        -preview=dip1000 \
        -Isource \
        -c "$source" \
        -of="$object" \
        2>"$stderr"
    then
        actual="pass"
    else
        actual="reject"
    fi

    if [ "$actual" = "$expectation" ]; then
        echo "PASS expected-$expectation: $name"

        # Expected rejections are diagnostic evidence too.
        # Show the first few lines so a false-positive rejection caused by
        # some unrelated module error remains visible.
        if [ "$expectation" = "reject" ] &&
           [ -s "$stderr" ]
        then
            echo '  compiler diagnostic:'
            sed 's/^/    /' "$stderr" | head -12
        fi
    else
        echo "FAIL expected-$expectation: $name"
        failures=$((failures + 1))

        if [ -s "$stderr" ]; then
            echo '  compiler diagnostic:'
            sed 's/^/    /' "$stderr" | head -50
        fi
    fi
}


cat > "$tmp_dir/positive.d" <<'D'
module imagery.raster.writable_view_positive;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult;

import imagery.raster.writable_view :
    tryMakeWritableRasterView;


/*
 * MUST PASS.
 *
 * This models the future retained-backing use:
 *
 * - resource metadata already exists and is borrowed;
 * - descriptor metadata already exists and is borrowed;
 * - the writable capability is consumed only inside those borrows.
 *
 * No local raw-pointer metadata table is manufactured here.
 */
@safe
bool exerciseWritableView(
    scope const(ResourceEntry)[] resources,
    scope const(PlaneDescriptor)[] descriptors
)
{
    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                1
            ),
            validation,
            certification
        );

    if (
        !validation.ok
        || !certification.ok
    )
    {
        return false;
    }


    if (
        !view.trySetSample(
            0,
            2,
            0,
            55
        )
    )
    {
        return false;
    }


    bool roiSuccess;

    auto roi =
        view.tryRoi(
            Region2D(
                1,
                0,
                2,
                1
            ),
            roiSuccess
        );

    if (!roiSuccess)
    {
        return false;
    }


    ubyte value;

    return
        roi.trySample(
            0,
            1,
            0,
            value
        );
}
D


cat > "$tmp_dir/local_escape.d" <<'D'
module imagery.raster.writable_view_negative_local_escape;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult;

import imagery.raster.writable_view :
    WritableRasterView,
    tryMakeWritableRasterView;


/*
 * MUST FAIL.
 *
 * Metadata is only scope-borrowed by this function.
 * Returning the resulting WritableRasterView would extend that borrow.
 */
@safe
WritableRasterView!ubyte escapeScopeBorrow(
    scope const(ResourceEntry)[] resources,
    scope const(PlaneDescriptor)[] descriptors
)
{
    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    return tryMakeWritableRasterView!ubyte(
        resources,
        descriptors,
        Region2D(
            0,
            0,
            4,
            1
        ),
        validation,
        certification
    );
}
D


cat > "$tmp_dir/global_escape.d" <<'D'
module imagery.raster.writable_view_negative_global_escape;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult;

import imagery.raster.writable_view :
    WritableRasterView,
    tryMakeWritableRasterView;


WritableRasterView!ubyte escaped;


/*
 * MUST FAIL.
 *
 * A capability tied to scope-borrowed retained metadata must not escape into
 * global storage.
 */
@safe
void storeScopeBorrowGlobally(
    scope const(ResourceEntry)[] resources,
    scope const(PlaneDescriptor)[] descriptors
)
{
    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                1
            ),
            validation,
            certification
        );

    escaped =
        view;
}
D


cat > "$tmp_dir/const_roi.d" <<'D'
module imagery.raster.writable_view_negative_const_roi;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult;

import imagery.raster.writable_view :
    tryMakeWritableRasterView;


/*
 * MUST FAIL.
 *
 * The backing borrows themselves are valid for this function.
 * Rejection must arise because writable child creation requires a mutable
 * WritableRasterView receiver.
 */
@safe
bool writableChildFromConstParent(
    scope const(ResourceEntry)[] resources,
    scope const(PlaneDescriptor)[] descriptors
)
{
    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    const parent =
        tryMakeWritableRasterView!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                1
            ),
            validation,
            certification
        );

    bool success;

    auto child =
        parent.tryRoi(
            Region2D(
                0,
                0,
                2,
                1
            ),
            success
        );

    return success && !child.empty;
}
D


cat > "$tmp_dir/raw_constructor_surface.d" <<'D'
module imagery.raster.writable_view_negative_raw_constructor_surface;

/*
 * MUST FAIL.
 *
 * Even another module inside imagery.raster must not manufacture writable
 * capability directly from PlaneDescriptor[] + Region2D.
 */
import imagery.raster.writable_view :
    makeWritableRasterViewAssumeCertified;

alias escapedRawConstructor =
    makeWritableRasterViewAssumeCertified;
D


cat > "$tmp_dir/external_surface.d" <<'D'
module raster_writable_view_negative_external_surface;

/*
 * MUST FAIL.
 *
 * WritableRasterView and its certifying factory remain package-internal during
 * E5.4d.1.
 */
import imagery.raster.writable_view :
    WritableRasterView,
    tryMakeWritableRasterView;

WritableRasterView!ubyte escaped;
D


compile_probe positive pass
compile_probe local_escape reject
compile_probe global_escape reject
compile_probe const_roi reject
compile_probe raw_constructor_surface reject
compile_probe external_surface reject

echo "FAILURES=$failures"

if [ "$failures" -ne 0 ]; then
    exit 1
fi
