#!/usr/bin/env bash

set -euo pipefail

ROOT="$(
    git rev-parse --show-toplevel
)"

EXP_ROOT="$ROOT/experiments/r0_3_raster_view"
OUT="${1:-$ROOT/build/codegen}"

mkdir -p "$OUT"

OUT="$(
    cd "$OUT"
    pwd
)"

cd "$EXP_ROOT"

echo '=== CODEGEN ENVIRONMENT ==='

ARCH="$(uname -m)"

detect_architecture()
{
    case "$ARCH" in
        x86_64|amd64)
            ARCH_NAME="x86-64"
            CPU_FLAGS=(
                -mcpu=x86-64-v3
            )
            ;;

        aarch64|arm64)
            ARCH_NAME="aarch64"
            CPU_FLAGS=()
            ;;

        *)
            echo "Unsupported architecture for this probe: $ARCH"
            return 1
            ;;
    esac
}

detect_architecture

echo "architecture=$ARCH_NAME"
echo "output=$OUT"

echo
ldc2 --version

echo
echo '=== RESOLVE DUB IMPORT PATHS ==='

mapfile -t DUB_IMPORT_PATHS < <(
    dub describe \
        --compiler=ldc2 \
        --data=import-paths \
        --data-list
)

IMPORT_FLAGS=(
    "-I=$EXP_ROOT"
)

for path in "${DUB_IMPORT_PATHS[@]}"; do
    if [ -n "$path" ]; then
        IMPORT_FLAGS+=(
            "-I=$path"
        )
    fi
done

printf '%s\n' "${DUB_IMPORT_PATHS[@]}" \
    > "$OUT/import-paths.txt"

echo "resolved ${#DUB_IMPORT_PATHS[@]} DUB import path(s)"

COMMON_FLAGS=(
    -O3
    -release
    -boundscheck=off
    -preview=dip1000
)

echo
echo '=== WRITE ENVIRONMENT METADATA ==='

{
    echo "git_commit=$(git -C "$ROOT" rev-parse HEAD)"
    echo "architecture=$ARCH_NAME"
    echo "uname=$(uname -a)"
    echo
    echo 'ldc_version:'
    ldc2 --version
    echo
    echo 'common_flags:'
    printf '%s\n' "${COMMON_FLAGS[@]}"
    echo
    echo 'cpu_flags:'
    printf '%s\n' "${CPU_FLAGS[@]}"
    echo
    echo 'import_paths:'
    printf '%s\n' "${DUB_IMPORT_PATHS[@]}"
} > "$OUT/environment.txt"

echo
echo '=== GENERATE NATIVE ASSEMBLY ==='

rm -f "$OUT/mir_codegen.s"

ldc2 \
    "${COMMON_FLAGS[@]}" \
    "${CPU_FLAGS[@]}" \
    "${IMPORT_FLAGS[@]}" \
    -c \
    -output-s \
    "-of=$OUT/mir_codegen.s" \
    mir_codegen.d

test -s "$OUT/mir_codegen.s"

echo "wrote $OUT/mir_codegen.s"

echo
echo '=== GENERATE LLVM IR ==='

rm -f "$OUT/mir_codegen.ll"

ldc2 \
    "${COMMON_FLAGS[@]}" \
    "${CPU_FLAGS[@]}" \
    "${IMPORT_FLAGS[@]}" \
    -c \
    -output-ll \
    "-of=$OUT/mir_codegen.ll" \
    mir_codegen.d

test -s "$OUT/mir_codegen.ll"

echo "wrote $OUT/mir_codegen.ll"

echo
echo '=== VERIFY EXPECTED SYMBOLS ==='

SYMBOLS=(
    mir_gain_universal
    mir_gain_canonical
    mir_gain_contiguous
    mir_gain_contiguous_flat
    raw_gain_flat
)

failures=0

for symbol in "${SYMBOLS[@]}"; do
    if grep -Fq "$symbol" "$OUT/mir_codegen.s"; then
        echo "$symbol: PASS"
    else
        echo "$symbol: MISSING"
        failures=$((failures + 1))
    fi
done

echo
echo '=== CODEGEN SUMMARY ==='

{
    echo "architecture=$ARCH_NAME"

    if [ "$ARCH_NAME" = "x86-64" ]; then
        ymm_mentions="$(
            {
                grep -Eo '\bymm[0-9]+\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        vmulps_mentions="$(
            {
                grep -Eo '\bvmulps\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        vaddps_mentions="$(
            {
                grep -Eo '\bvaddps\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        echo "ymm_mentions=$ymm_mentions"
        echo "vmulps_mentions=$vmulps_mentions"
        echo "vaddps_mentions=$vaddps_mentions"
    else
        vector_4s_mentions="$(
            {
                grep -Eo '\bv[0-9]+\.4s\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        fmul_mentions="$(
            {
                grep -Eo '\bfmul\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        fadd_mentions="$(
            {
                grep -Eo '\bfadd\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        fmla_mentions="$(
            {
                grep -Eo '\bfmla\b' \
                    "$OUT/mir_codegen.s" || true
            } |
            wc -l
        )"

        echo "vector_4s_mentions=$vector_4s_mentions"
        echo "fmul_mentions=$fmul_mentions"
        echo "fadd_mentions=$fadd_mentions"
        echo "fmla_mentions=$fmla_mentions"
    fi
} | tee "$OUT/summary.txt"

echo
echo '=== CONTIGUOUS FLAT ASSEMBLY EXCERPT ==='

awk '
    /^mir_gain_contiguous_flat:/ {
        printing = 1
        count = 0
    }

    printing && count < 100 {
        print
        count++
    }

    printing && count >= 100 {
        printing = 0
    }
' "$OUT/mir_codegen.s" \
    | tee "$OUT/contiguous-flat-excerpt.txt"

echo
echo '=== RAW FLAT ASSEMBLY EXCERPT ==='

awk '
    /^raw_gain_flat:/ {
        printing = 1
        count = 0
    }

    printing && count < 100 {
        print
        count++
    }

    printing && count >= 100 {
        printing = 0
    }
' "$OUT/mir_codegen.s" \
    | tee "$OUT/raw-flat-excerpt.txt"

echo
echo "FAILURES=$failures"

if [ "$failures" -ne 0 ]; then
    echo 'R0.3 ARCHITECTURE CODEGEN: FAIL'
    false
fi

echo 'R0.3 ARCHITECTURE CODEGEN: PASS'
