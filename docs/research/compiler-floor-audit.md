# Compiler floor audit

Date: 2026-09-19

## Purpose

Determine the oldest compiler/frontend generations that `imagery-d` can
reasonably support without compatibility shims or architecture changes.

The audit distinguishes:

1. source/frontend compatibility;
2. concrete compiler-package compatibility on current CI platforms.

These are intentionally not treated as the same thing.

## Source/frontend floor

The source/frontend floor is DMD/Phobos 2.101.

`imagery-d` uses the following `std.typecons` facilities in its retained
resource implementation:

- `SafeRefCounted`;
- `safeRefCounted`;
- `borrow`.

They are available in Phobos 2.101 but not in Phobos 2.100.

A compatibility layer for older Phobos releases is not justified by a current
consumer and was therefore rejected.

The corresponding LDC generation is LDC 1.31.0, based on the DMD 2.101
frontend.

## Validated platform floors

The minimum compiler packages validated on the current GitHub-hosted runner
platforms are:

| Platform | DMD | LDC |
| --- | --- | --- |
| Linux x86-64 | 2.101.2 | 1.31.0 |
| Linux ARM64 | not separately required | 1.31.0 |
| Windows x86-64 | 2.101.2 | 1.31.0 |
| macOS x86-64 | 2.112.1 | 1.41.0 |
| macOS ARM64 | not separately required | 1.41.0 |
| Windows ARM64 | experimental / current compiler only | experimental / current compiler only |

These are tested package floors, not claims that the source language itself
requires the higher macOS versions.

## macOS boundary

Older compiler packages fail on current macOS 15 runners before an
`imagery-d` semantic incompatibility can be demonstrated.

Observed DMD boundary on macOS x86-64:

- DMD 2.110.0: compiler executable segfaults at `dmd --version`;
- DMD 2.111.0: compiler executable segfaults at `dmd --version`;
- DMD 2.112.1: build, tests and all raster compile probes pass.

Observed LDC boundary on macOS x86-64 and ARM64:

- LDC 1.40.1: compiler runs and builds, but produced test executable
  segfaults;
- LDC 1.41.0: build, tests and all raster compile probes pass.

LDC 1.41.0 upstream also documents a fix for bundled macOS executables
crashing on macOS 15.4.

Therefore the macOS package floors are deliberately higher than the
source/frontend floor.

## Linux ARM64 DUB note

The first Linux ARM64 LDC 1.31.0 attempt failed before compiler execution
because `setup-dlang` attempted to install DUB 1.40.0, for which no
`linux-arm64` release binary was available.

Repeating the job with the compiler-bundled DUB passed completely.

This was an audit-harness/tool-distribution issue, not an `imagery-d`
compatibility failure.

## Audit runs

The research was performed incrementally rather than by selecting an arbitrary
recent minimum.

Relevant GitHub Actions runs:

| Run | Scope | Result |
| --- | --- | --- |
| 35445193795 | frontend 2.108–2.113, DMD/LDC, Linux x86-64 | all pass |
| 35445669305 | frontend 2.101–2.107, DMD/LDC, Linux x86-64 | all pass |
| 35445923836 | frontend 2.094–2.100, DMD/LDC, Linux x86-64 | all fail at build |
| 35446251861 | initial cross-platform 2.101 boundary | mixed; platform/tooling limits exposed |
| 35447956773 | Linux ARM64 retry and macOS midpoint | Linux ARM64 passes; macOS old toolchains fail |
| 35448209752 | macOS DMD 2.110 / LDC 1.40.1 | fail |
| 35448732034 | macOS DMD 2.112.1 / LDC 1.42.0 | all pass |
| 35448995061 | macOS DMD 2.111.0 / LDC 1.41.0 | LDC passes; DMD fails before build |

All passing jobs exercised:

- `dub build`;
- `dub test`;
- raster lifetime compile probes;
- raster construction lifetime compile probes;
- raster owned-resource compile probes;
- raster public-import compile probes;
- raster execution lifetime compile probes;
- raster target lifetime compile probes;
- raster writable-view lifetime compile probes.

## Support policy

`imagery-d` should continue to test current DMD and LDC releases separately
from minimum supported compiler packages.

The minimum versions are compatibility baselines, not a promise to avoid
useful newer language or library functionality indefinitely.

Raising a minimum version later is acceptable when justified by a concrete
consumer, correctness improvement, maintenance benefit or measured
implementation advantage.

Older versions should not receive compatibility shims without such a reason.
