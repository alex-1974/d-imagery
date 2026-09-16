#!/usr/bin/env bash

compiler="${1:-${DC:-dmd}}"

repo_root="$(
    cd "$(dirname "$0")/../.." >/dev/null 2>&1
    pwd
)"

tmp_dir="${TMPDIR:-/tmp}/d-imagery-raster-lifetime-$$"

mkdir -p "$tmp_dir"

failures=0


cat > "$tmp_dir/positive.d" <<'D'
module raster_lifetime_positive;

/*
 * Static lifetime is intentional here.
 *
 * Release-counter lifetime must not interfere with the RasterView
 * borrow/escape property being tested by this compile probe.
 */
private size_t[3] releases;

import imagery.raster.backing :
    makeLifetimeTestLease;

@safe
void validBorrow()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

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


cat > "$tmp_dir/return_view.d" <<'D'
module raster_lifetime_negative_return_view;

/*
 * Static lifetime is intentional here.
 *
 * Release-counter lifetime must not interfere with the RasterView
 * borrow/escape property being tested by this compile probe.
 */
private size_t[3] releases;

import imagery.raster.backing :
    RasterLease,
    makeLifetimeTestLease;

import imagery.raster.view :
    RasterView;

/*
 * MUST FAIL:
 *
 * Returned RasterView borrows storage owned only by local `lease`.
 */
@safe
RasterView!ubyte escapeView()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

    return lease.view();
}
D


cat > "$tmp_dir/return_roi.d" <<'D'
module raster_lifetime_negative_return_roi;

/*
 * Static lifetime is intentional here.
 *
 * Release-counter lifetime must not interfere with the RasterView
 * borrow/escape property being tested by this compile probe.
 */
private size_t[3] releases;

import imagery.raster.backing :
    makeLifetimeTestLease;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    RasterView;

/*
 * MUST FAIL:
 *
 * ROI remains transitively bound to the local lease.
 */
@safe
RasterView!ubyte escapeRoi()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

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
module raster_lifetime_negative_global;

/*
 * Static lifetime is intentional here.
 *
 * Release-counter lifetime must not interfere with the RasterView
 * borrow/escape property being tested by this compile probe.
 */
private size_t[3] releases;

import imagery.raster.backing :
    makeLifetimeTestLease;

import imagery.raster.view :
    RasterView;

RasterView!ubyte escaped;

/*
 * MUST FAIL:
 *
 * A borrowed view may not escape into global storage.
 */
@safe
void storeGlobally()
{
    auto lease =
        makeLifetimeTestLease(
            releases.ptr
        );

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
            sed -n '1,80p' "$log_file" | sed 's/^/    /'
        else
            echo "FAIL expected-rejection: $name compiled successfully"
            failures=$((failures + 1))
        fi
    fi
}


echo "compiler=$compiler"

compile_probe positive pass
compile_probe return_view reject
compile_probe return_roi reject
compile_probe global reject

echo "FAILURES=$failures"

rm -rf "$tmp_dir"

[ "$failures" -eq 0 ]
