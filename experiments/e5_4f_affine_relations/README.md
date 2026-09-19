# E5.4f affine-relation research harness

This directory preserves the research programs used to establish the affine
relation and checked-wide-arithmetic results recorded for E5.4f.

## Provenance

The five programs below were originally executed as temporary research probes
under `/tmp` during the E5.4f.3–E5.4f.5b investigation.

They were recovered on 2026-09-19 and copied into this repository
byte-for-byte.

Their SHA-256 hashes are recorded in `SHA256SUMS`.

The files below `original/` are retained as historical research evidence and
must not be reformatted, refactored or otherwise modified merely to improve
their style.

If later work requires a changed algorithm or a maintained production-derived
verification harness, add that separately rather than silently changing the
recovered originals.

## Original probes

| Stage | Source | Verified research result |
| --- | --- | --- |
| E5.4f.3 | `original/e5_4f_3/injectivity.d` | 30,625 finite-grid injectivity cases |
| E5.4f.4 | `original/e5_4f_4/affine_overlap.d` | 360,000 exact affine byte-overlap cases |
| E5.4f.5b.1 | `original/e5_4f_5b_1/wide_signed.d` | 40,401 arithmetic and 8,040 division cases |
| E5.4f.5b.2a | `original/e5_4f_5b_2a/wide_diophantine.d` | 792,756 bounded wide Diophantine cases |
| E5.4f.5b.2b | `original/e5_4f_5b_2b/wide_affine_overlap.d` | 360,000 wide affine-overlap cases |

The wide affine-overlap probe also verifies:

- the bounding-envelope false-positive counterexample;
- full-address-width edge cases;
- `skippedUnrepresentable=0`.

## Replay

Assertions are part of the verification and therefore must remain enabled.

Run with DMD:

```bash
experiments/e5_4f_affine_relations/run.sh dmd
```

Run with LDC:

```bash
experiments/e5_4f_affine_relations/run.sh ldc2
```

The runner:

1. verifies every original source against `SHA256SUMS`;
2. builds each source without `-release`;
3. executes it;
4. requires empty stderr;
5. compares complete stdout against the recovered expected result.

Build products are created below the system temporary directory and removed
after the replay.

## Recovery validation

Before this durable wrapper was added, the recovered originals were replayed
unchanged with:

- DMD 2.111.0;
- LDC 1.41.0 / LLVM 19.1.7;
- Linux x86-64, Skylake host.

Both compilers produced byte-identical stdout for every probe and reproduced
all documented case counts.

## Relationship to production

These programs establish research evidence for the contracts documented in
`docs/architecture/raster-operations.md`.

They are not production implementations and are not a second implementation
API.

Production mapping remains consumer-driven. In particular, successful replay
of these probes does not by itself justify introducing a generic public
wide-integer, affine-target, alias-proof or Diophantine abstraction.
