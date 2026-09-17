#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/d-imagery-raster-execution-lifetime-$$"

mkdir -p "$tmp_dir"

failures=0


if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required"
    rm -rf "$tmp_dir"
    exit 1
fi


# Resolve every import path exactly as DUB sees the current root package and
# its Mir dependencies.
if ! (
    cd "$repo_root" &&
    dub describe --compiler="$compiler"
) >"$tmp_dir/describe.json"
then
    echo "ERROR: dub describe failed"
    rm -rf "$tmp_dir"
    exit 1
fi


mapfile -t import_paths < <(
    jq -r '
        .packages[]
        | .path as $base
        | (.importPaths // [])[]
        | if startswith("/")
          then .
          else ($base + "/" + .)
          end
    ' "$tmp_dir/describe.json"
)

import_args=()

for path in "${import_paths[@]}"
do
    import_args+=("-I$path")
done


cat > "$tmp_dir/positive.d" <<'D'
module imagery.raster.execution_lifetime_positive;

/*
 * Static lifetime is intentional.
 *
 * The release-counter pointer must not influence the RasterLease/RasterView/
 * Mir-slice borrow relation being tested.
 */
private size_t[3] releases;

import imagery.raster.backing :
    makeLifetimeTestLease;

import imagery.raster.internal.mir_adapter :
    asMirUniversal;


/*
 * MUST PASS.
 *
 * The Mir execution view is created and consumed while the originating
 * RasterLease remains alive.
 */
@safe
void validMirBorrow()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

    auto view =
        lease.view();

    auto plane =
        asMirUniversal(
            view,
            0
        );

    assert(plane[0, 0] == 0);
    assert(plane[1, 2] == 12);
}
D


cat > "$tmp_dir/return_mir.d" <<'D'
module imagery.raster.execution_lifetime_negative_return_mir;

/*
 * Static lifetime is intentional.
 *
 * The release-counter pointer must not influence the lifetime property being
 * tested.
 */
private size_t[3] releases;

import imagery.raster.backing :
    makeLifetimeTestLease;

import imagery.raster.internal.mir_adapter :
    MirUniversalPlane,
    asMirUniversal;


/*
 * MUST FAIL.
 *
 * The returned Mir slice ultimately aliases pixel storage retained only by
 * the local RasterLease.
 */
@safe
MirUniversalPlane!ubyte escapeMirPlane()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

    auto view =
        lease.view();

    return asMirUniversal(
        view,
        0
    );
}
D


cat > "$tmp_dir/external_surface.d" <<'D'
module raster_execution_negative_external_surface;

/*
 * MUST FAIL.
 *
 * Mir execution types/adapters are package-internal implementation details,
 * not public d-imagery raster API.
 */
import imagery.raster.internal.mir_adapter :
    MirUniversalPlane,
    asMirUniversal;

MirUniversalPlane!ubyte escapedType;
D


cat > "$tmp_dir/fixed_lane_external_surface.d" <<'D'
module raster_execution_negative_fixed_lane_external_surface;

/*
 * MUST FAIL.
 *
 * Fixed-lane execution kernels are package-internal implementation details.
 * Code outside imagery.raster must not acquire the specialized reduction
 * entry point directly.
 */
import imagery.raster.internal.fixed_lane_kernels :
    fixedLane4SumFloatToDoubleContiguous1D;

alias escapedFixedLaneReduction =
    fixedLane4SumFloatToDoubleContiguous1D;
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
            "${import_args[@]}" \
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
            sed -n '1,120p' "$log_file"
            failures=$((failures + 1))
        fi
    else
        if [ "$compiled" = "no" ]; then
            echo "PASS expected-rejection: $name"
            echo "  compiler diagnostic:"
            sed -n '1,100p' "$log_file" |
                sed 's/^/    /'
        else
            echo "FAIL expected-rejection: $name compiled successfully"
            failures=$((failures + 1))
        fi
    fi
}


echo "compiler=$compiler"

compile_probe positive pass
compile_probe return_mir reject
compile_probe external_surface reject
compile_probe fixed_lane_external_surface reject

echo "FAILURES=$failures"

rm -rf "$tmp_dir"

[ "$failures" -eq 0 ]
