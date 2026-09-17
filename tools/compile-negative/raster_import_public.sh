#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/d-imagery-raster-import-public-$$"

mkdir -p "$tmp_dir"

failures=0


cat > "$tmp_dir/positive_safe.d" <<'D'
module raster_import_public_positive_safe;

import imagery.raster :
    OwnedByteResource,
    OwnedRasterImportError,
    OwnedRasterImportResult,
    OwnedRasterResourceDisposition,
    PlaneByteLayout,
    RasterLease,
    Region2D,
    tryImportOwnedRaster;


@safe
OwnedRasterImportResult importFromSafeCode(
    ref OwnedByteResource resource,
    ref RasterLease!ubyte lease
)
{
    PlaneByteLayout[1] planes =
    [
        PlaneByteLayout(
            0,
            4,
            1
        )
    ];


    auto result =
        tryImportOwnedRaster!ubyte(
            resource,
            planes[],
            Region2D(
                0,
                0,
                4,
                1
            ),
            lease
        );


    if (result.ok)
    {
        assert(
            result.error
            == OwnedRasterImportError.none
        );

        assert(
            result.resourceDisposition
            == OwnedRasterResourceDisposition.transferredToLease
        );
    }


    return result;
}
D


cat > "$tmp_dir/internal_surface.d" <<'D'
module raster_import_public_negative_internal_surface;


/*
 * MUST FAIL:
 *
 * Package-internal import mechanics must not be exported by imagery.raster.
 */
import imagery.raster :
    SingleResourceRasterImportError,
    SingleResourceRasterImportResult,
    importSingleOwnedResource;
D


cat > "$tmp_dir/result_constructor.d" <<'D'
module raster_import_public_negative_result_constructor;

import imagery.raster :
    OwnedRasterImportError,
    OwnedRasterImportResult,
    OwnedRasterResourceDisposition;


/*
 * MUST FAIL:
 *
 * Public callers may not fabricate an arbitrary successful ownership result
 * through the module-private constructor.
 */
void invalidResultConstruction()
{
    auto result =
        OwnedRasterImportResult(
            OwnedRasterImportError.none,
            size_t.max,
            OwnedRasterResourceDisposition.transferredToLease
        );
}
D


cat > "$tmp_dir/result_mutation.d" <<'D'
module raster_import_public_negative_result_mutation;

import imagery.raster :
    OwnedRasterImportError,
    OwnedRasterImportResult;


/*
 * MUST FAIL:
 *
 * Public callers may inspect but may not fabricate error/disposition states.
 */
void invalidResultMutation()
{
    OwnedRasterImportResult result;

    result.error_ =
        OwnedRasterImportError.none;
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
            -of="$object_file" \
            "$source_file"
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
            sed -n '1,160p' "$log_file"
            failures=$((failures + 1))
        fi
    else
        if [ "$compiled" = "no" ]; then
            echo "PASS expected-rejection: $name"
            echo "  compiler diagnostic:"
            sed -n '1,120p' "$log_file" | sed 's/^/    /'
        else
            echo "FAIL expected-rejection: $name compiled successfully"
            failures=$((failures + 1))
        fi
    fi
}


echo "compiler=$compiler"

compile_probe positive_safe pass
compile_probe internal_surface reject
compile_probe result_constructor reject
compile_probe result_mutation reject

echo "FAILURES=$failures"

rm -rf "$tmp_dir"

if [ "$failures" -eq 0 ]; then
    true
else
    false
fi
