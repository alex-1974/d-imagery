#!/usr/bin/env bash

set -eu

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <d-compiler>" >&2
    echo "example: $0 dmd" >&2
    echo "example: $0 ldc2" >&2
    exit 2
fi

COMPILER="$1"

if ! command -v "$COMPILER" >/dev/null 2>&1; then
    echo "compiler not found: $COMPILER" >&2
    exit 2
fi

hash_file()
{
    file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return
    fi

    python3 - "$file" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

h = sha256()

with Path(sys.argv[1]).open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)

print(h.hexdigest())
PY
}

echo '=== E5.4f AFFINE RELATIONS — ORIGINAL REPLAY ==='
echo "compiler=$COMPILER"
"$COMPILER" --version
echo

echo '=== SOURCE INTEGRITY ==='

while read -r expected relative
do
    file="$ROOT/$relative"

    if [ ! -f "$file" ]; then
        echo "$relative: MISSING" >&2
        exit 1
    fi

    actual="$(hash_file "$file")"

    if [ "$actual" != "$expected" ]; then
        echo "$relative: HASH FAIL" >&2
        echo "expected=$expected" >&2
        echo "actual  =$actual" >&2
        exit 1
    fi

    echo "$relative: PASS"
done < "$ROOT/SHA256SUMS"

RUN="$(mktemp -d "${TMPDIR:-/tmp}/imagery-d-e5_4f-replay.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT

run_case()
{
    name="$1"
    source="$2"
    expected="$3"

    exe="$RUN/$name"
    out="$RUN/$name.out"
    err="$RUN/$name.err"
    expected_file="$RUN/$name.expected"

    echo
    echo "=== $name ==="

    "$COMPILER" "$ROOT/$source" "-of=$exe"

    "$exe" >"$out" 2>"$err"

    if [ -s "$err" ]; then
        echo "$name: unexpected stderr" >&2
        cat "$err" >&2
        exit 1
    fi

    printf '%s\n' "$expected" > "$expected_file"

    if ! cmp -s "$expected_file" "$out"; then
        echo "$name: OUTPUT FAIL" >&2
        diff -u "$expected_file" "$out" || true
        exit 1
    fi

    cat "$out"
    echo "$name: PASS"
}

run_case \
    "e5_4f_3_injectivity" \
    "original/e5_4f_3/injectivity.d" \
"verifiedCases=30625
affine2D injectivity formula: PASS"

run_case \
    "e5_4f_4_affine_overlap" \
    "original/e5_4f_4/affine_overlap.d" \
"verifiedCases=360000
exact affine 2D byte-overlap relation: PASS"

run_case \
    "e5_4f_5b_1_wide_signed" \
    "original/e5_4f_5b_1/wide_signed.d" \
"arithmeticCases=40401
divisionCases=8040
sign+magnitude Cent arithmetic: PASS
address difference without signed narrowing: PASS
ptrdiff.min magnitude handling: PASS
wide floor/ceil division: PASS"

run_case \
    "e5_4f_5b_2a_wide_diophantine" \
    "original/e5_4f_5b_2a/wide_diophantine.d" \
"verifiedCases=792756
bounded wide Diophantine equivalence: PASS
full-width modular cases: PASS"

run_case \
    "e5_4f_5b_2b_wide_affine_overlap" \
    "original/e5_4f_5b_2b/wide_affine_overlap.d" \
"verifiedCases=360000
skippedUnrepresentable=0
wide affine 2D overlap equivalence: PASS
bounding-envelope counterexample: PASS
full-address edge cases: PASS"

echo
echo '=== RESULT ==='
echo 'original E5.4f affine-relations replay: PASS'
