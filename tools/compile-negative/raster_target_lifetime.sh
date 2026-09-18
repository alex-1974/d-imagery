#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/imagery-d-raster-target-lifetime-$$"

mkdir -p "$tmp_dir"

failures=0


if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required"
    rm -rf "$tmp_dir"
    false
else
    if ! (
        cd "$repo_root" &&
        dub describe --compiler="$compiler"
    ) >"$tmp_dir/describe.json"
    then
        echo "ERROR: dub describe failed"
        rm -rf "$tmp_dir"
        false
    else
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
module imagery.raster.target_lifetime_positive;

import imagery.raster.internal.target :
    RasterTargetPlane,
    tryBorrowContiguousTarget;

import imagery.raster.internal.mir_target_adapter :
    MirTargetContiguousPlane,
    asMirTargetContiguous;


/*
 * MUST PASS:
 *
 * caller storage -> RasterTargetPlane -> writable Mir slice
 */
@safe
RasterTargetPlane!int targetFromCaller(
    return scope int[] storage
)
{
    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage,
            storage.length,
            1,
            success
        );

    assert(success);

    return target;
}


@safe
MirTargetContiguousPlane!int mirFromCaller(
    return scope int[] storage
)
{
    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage,
            storage.length,
            1,
            success
        );

    assert(success);

    return asMirTargetContiguous(
        target
    );
}
D


        cat > "$tmp_dir/return_target.d" <<'D'
module imagery.raster.target_lifetime_negative_return_target;

import imagery.raster.internal.target :
    RasterTargetPlane,
    tryBorrowContiguousTarget;


/*
 * MUST FAIL:
 *
 * Target aliases local storage.
 */
@safe
RasterTargetPlane!int escapeTarget()
{
    int[4] data =
        [1, 2, 3, 4];

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            data[],
            4,
            1,
            success
        );

    assert(success);

    return target;
}
D


        cat > "$tmp_dir/return_mir.d" <<'D'
module imagery.raster.target_lifetime_negative_return_mir;

import imagery.raster.internal.mir_target_adapter :
    MirTargetContiguousPlane,
    asMirTargetContiguous;

import imagery.raster.internal.target :
    tryBorrowContiguousTarget;


/*
 * MUST FAIL:
 *
 * Mir target ultimately aliases local storage.
 */
@safe
MirTargetContiguousPlane!int escapeMir()
{
    int[4] data =
        [1, 2, 3, 4];

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            data[],
            4,
            1,
            success
        );

    assert(success);

    return asMirTargetContiguous(
        target
    );
}
D


        cat > "$tmp_dir/global_target.d" <<'D'
module imagery.raster.target_lifetime_negative_global;

import imagery.raster.internal.target :
    RasterTargetPlane,
    tryBorrowContiguousTarget;


RasterTargetPlane!int escaped;


/*
 * MUST FAIL:
 *
 * Borrowed target may not escape into global storage.
 */
@safe
void escapeGlobally()
{
    int[4] data =
        [1, 2, 3, 4];

    bool success;

    escaped =
        tryBorrowContiguousTarget(
            data[],
            4,
            1,
            success
        );

    assert(success);
}
D


        cat > "$tmp_dir/external_surface.d" <<'D'
module raster_target_negative_external_surface;


/*
 * MUST FAIL:
 *
 * Writable target semantics and Mir adapters remain internal implementation
 * details.
 */
import imagery.raster.internal.target :
    RasterTargetPlane,
    tryBorrowContiguousTarget;

import imagery.raster.internal.mir_target_adapter :
    MirTargetContiguousPlane,
    asMirTargetContiguous;


RasterTargetPlane!int target;
MirTargetContiguousPlane!int plane;
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
        compile_probe return_target reject
        compile_probe return_mir reject
        compile_probe global_target reject
        compile_probe external_surface reject

        echo "FAILURES=$failures"

        rm -rf "$tmp_dir"

        [ "$failures" -eq 0 ]
    fi
fi
