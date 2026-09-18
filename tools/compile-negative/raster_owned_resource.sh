#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/imagery-d-raster-owned-resource-$$"

mkdir -p "$tmp_dir"

failures=0


cat > "$tmp_dir/positive.d" <<'D'
module raster_owned_resource_positive;

import core.stdc.stdlib :
    malloc;

import std.algorithm.mutation :
    move;

import imagery.raster :
    OwnedByteResource,
    tryAdoptMallocResource;


@system
void validMoveOnlyOwnership()
{
    auto memory =
        malloc(16);

    assert(memory !is null);


    OwnedByteResource first;

    assert(
        tryAdoptMallocResource(
            memory,
            16,
            first
        )
    );


    auto second =
        move(first);

    assert(!first.ownsResource);
    assert(second.ownsResource);
}
D


cat > "$tmp_dir/copy.d" <<'D'
module raster_owned_resource_negative_copy;

import core.stdc.stdlib :
    malloc;

import imagery.raster :
    OwnedByteResource,
    tryAdoptMallocResource;


/*
 * MUST FAIL:
 *
 * OwnedByteResource carries one physical release obligation and therefore may
 * not be copied.
 */
@system
void invalidCopy()
{
    auto memory =
        malloc(16);

    OwnedByteResource first;

    tryAdoptMallocResource(
        memory,
        16,
        first
    );


    auto second =
        first;
}
D


cat > "$tmp_dir/safe_adopt.d" <<'D'
module raster_owned_resource_negative_safe_adopt;

import imagery.raster :
    OwnedByteResource,
    tryAdoptMallocResource;


/*
 * MUST FAIL:
 *
 * @safe code cannot assert ownership and free()-compatibility of an arbitrary
 * raw pointer.
 */
@safe
void invalidSafeAdoption()
{
    OwnedByteResource resource;

    tryAdoptMallocResource(
        null,
        0,
        resource
    );
}
D


cat > "$tmp_dir/raw_surface.d" <<'D'
module raster_owned_resource_negative_raw_surface;


/*
 * MUST FAIL:
 *
 * Raw resource/callback types are not part of the public imagery.raster API.
 */
import imagery.raster :
    ResourceEntry,
    ReleaseFn;
D


cat > "$tmp_dir/resource_access_surface.d" <<'D'
module raster_owned_resource_negative_resource_access_surface;

/*
 * MUST FAIL.
 *
 * Raw retained-resource access provenance is package-internal storage
 * machinery. Public callers receive semantic raster capabilities instead.
 */
import imagery.raster.resource :
    ResourceAccess;

ResourceAccess escapedAccess;
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
compile_probe copy reject
compile_probe safe_adopt reject
compile_probe raw_surface reject
compile_probe resource_access_surface reject

echo "FAILURES=$failures"

rm -rf "$tmp_dir"

if [ "$failures" -eq 0 ]; then
    true
else
    false
fi
