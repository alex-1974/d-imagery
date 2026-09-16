#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/d-imagery-raster-construction-lifetime-$$"

mkdir -p "$tmp_dir"

failures=0


cat > "$tmp_dir/support.d" <<'D'
module imagery.raster.probe_support;

import imagery.raster.backing :
    RasterLease;

import imagery.raster.construction :
    constructRetainedRaster;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;


/*
 * Static storage deliberately avoids introducing another lifetime into the
 * compile probes.
 *
 * The resource requires no release callback because its lifetime is the
 * complete program lifetime.
 */
private ubyte pixel = 42;


/*
 * Returning RasterLease is expected to be valid.
 *
 * RasterLease is the owning/retaining capability. Unlike RasterView it does
 * not borrow from this local function.
 *
 * @trusted is used only for assembling package-internal physical metadata.
 */
@trusted
RasterLease!ubyte makeConstructedLease()
{
    ResourceEntry[1] resources =
    [
        ResourceEntry(
            &pixel,
            1,
            null,
            null
        )
    ];

    PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            &pixel,
            1,
            1
        )
    ];

    RasterLease!ubyte lease;

    const result =
        constructRetainedRaster!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                1,
                1
            ),
            lease
        );

    assert(result.ok);

    return lease;
}
D


cat > "$tmp_dir/positive.d" <<'D'
module imagery.raster.probe_positive;

import imagery.raster.probe_support :
    makeConstructedLease;


@safe
void validConstructedBorrow()
{
    auto lease =
        makeConstructedLease();

    auto view =
        lease.view();

    ubyte value;

    assert(
        view.trySample(
            0,
            0,
            0,
            value
        )
    );
}
D


cat > "$tmp_dir/return_lease.d" <<'D'
module imagery.raster.probe_positive_return_lease;

import imagery.raster.backing :
    RasterLease;

import imagery.raster.probe_support :
    makeConstructedLease;


/*
 * MUST COMPILE:
 *
 * RasterLease carries retained ownership and may leave this scope.
 */
@safe
RasterLease!ubyte returnOwningLease()
{
    auto lease =
        makeConstructedLease();

    return lease;
}
D


cat > "$tmp_dir/return_view.d" <<'D'
module imagery.raster.probe_negative_return_view;

import imagery.raster.probe_support :
    makeConstructedLease;

import imagery.raster.view :
    RasterView;


/*
 * MUST FAIL:
 *
 * The constructed lease is local.
 * RasterView borrows from it and therefore may not be returned.
 */
@safe
RasterView!ubyte escapeConstructedView()
{
    auto lease =
        makeConstructedLease();

    return lease.view();
}
D


cat > "$tmp_dir/return_roi.d" <<'D'
module imagery.raster.probe_negative_return_roi;

import imagery.raster.probe_support :
    makeConstructedLease;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    RasterView;


/*
 * MUST FAIL:
 *
 * ROI transitively borrows from the RasterView and therefore from the local
 * constructed RasterLease.
 */
@safe
RasterView!ubyte escapeConstructedRoi()
{
    auto lease =
        makeConstructedLease();

    auto view =
        lease.view();

    bool success;

    auto roi =
        view.tryRoi(
            Region2D(
                0,
                0,
                1,
                1
            ),
            success
        );

    assert(success);

    return roi;
}
D


cat > "$tmp_dir/global.d" <<'D'
module imagery.raster.probe_negative_global;

import imagery.raster.probe_support :
    makeConstructedLease;

import imagery.raster.view :
    RasterView;


RasterView!ubyte escaped;


/*
 * MUST FAIL:
 *
 * A view borrowed from a locally constructed RasterLease may not escape into
 * global storage.
 */
@safe
void storeConstructedViewGlobally()
{
    auto lease =
        makeConstructedLease();

    escaped =
        lease.view();
}
D


compile_probe()
{
    name="$1"
    expectation="$2"

    source_file="$tmp_dir/$name.d"
    object_file="$tmp_dir/$name.o"
    log_file="$tmp_dir/$name.log"

    if (
        cd "$repo_root" &&
        "$compiler" \
            -c \
            -preview=dip1000 \
            -unittest \
            -Isource \
            -I"$tmp_dir" \
            -of="$object_file" \
            "$source_file" \
            "$tmp_dir/support.d"
    ) >"$log_file" 2>&1
    then
        compiled=yes
    else
        compiled=no
    fi

    if [ "$expectation" = "pass" ]; then
        if [ "$compiled" = "yes" ]; then
            echo "PASS expected-compile: $name"
        else
            echo "FAIL expected-compile: $name"
            sed -n '1,140p' "$log_file"
            failures=$((failures + 1))
        fi
    else
        if [ "$compiled" = "no" ]; then
            echo "PASS expected-rejection: $name"
            echo "  compiler diagnostic:"
            sed -n '1,100p' "$log_file" | sed 's/^/    /'
        else
            echo "FAIL expected-rejection: $name compiled successfully"
            failures=$((failures + 1))
        fi
    fi
}


echo "compiler=$compiler"

compile_probe positive pass
compile_probe return_lease pass
compile_probe return_view reject
compile_probe return_roi reject
compile_probe global reject

echo "FAILURES=$failures"

rm -rf "$tmp_dir"

[ "$failures" -eq 0 ]
