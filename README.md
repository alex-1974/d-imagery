# imagery-d

`imagery-d` is an experimental high-performance image engine written in D,
designed primarily for large geospatial imagery such as aerial photographs,
orthophotos and satellite imagery.

The initial target application is an interactive OpenStreetMap editor, but the
engine itself is intended to remain independent of OSM and generally useful for
geospatial and large-image processing.

## Status

Active core-engine implementation following the initial research and
architecture phase.

The retained raster foundation now includes:

- owned-resource import and retained backing lifetime;
- descriptor-space regions and read-only `RasterView` semantics;
- signed row and sample strides;
- per-plane execution-layout classification;
- internal Mir adapters and scalar reference kernels;
- evidence-driven reduction and copy specialization;
- checked `ubyte -> float` conversion;
- per-resource read/write provenance;
- writable-backing certification;
- a package-internal semantic `WritableRasterView`;
- a lease-bound package-internal writable borrow from `RasterLease`.

The writable semantic and execution layers are not public yet. E5.4e is
complete: retained writable backing can flow through the package-internal
`WritableRasterView` into the existing `RasterTargetPlane` execution boundary
used by checked copy and exact conversion consumers.

E5.4f is now in progress and is redesigning the public operation contracts from
their required semantics rather than exposing the existing internal
dispatchers. Stable public operation exposure remains deferred to E5.4g.

The public API remains experimental. Performance-sensitive implementation is
developed from measured evidence and validated with both DMD and LDC.

## Primary goals

- process imagery substantially larger than available RAM;
- bounded and configurable memory consumption;
- efficient regions, windows and neighbourhood access;
- low-copy and zero-copy views where appropriate;
- efficient tiled and streamed processing;
- predictable halo/context handling;
- support interactive workloads;
- SIMD-friendly CPU processing;
- scalable multithreaded execution;
- clear separation between image algorithms and execution strategy;
- retain a path toward future GPU processing;
- support geospatial raster sources without coupling the processing core to
  a particular file format or provider.

## Non-goals of the initial phase

The initial research phase does not attempt to implement a comprehensive image
processing library.

Advanced work such as:

- radiometric normalization;
- shadow correction;
- image enhancement;
- feature extraction;
- segmentation;
- machine-learning inference;

is deferred until the image-engine foundations have been evaluated and
stabilized.

## Repository layout

    source/imagery/       library implementation
    tests/                correctness tests
    docs/adr/             architecture decision records
    docs/research/        research results
    benchmark/scenes/     reproducible test-scene definitions
    benchmark/sources/    imagery-source definitions
    benchmark/tools/      benchmark corpus tooling
    data/                 local, non-versioned imagery and results

## Benchmark imagery

Satellite and aerial imagery is not stored in Git.

The repository will instead contain reproducible scene definitions, source
metadata, retrieval parameters, provenance information and hashes.

Downloaded imagery lives below `data/` and remains local.

## Build

    dub build
    dub test

Performance-sensitive work will be tested with both DMD and LDC. LDC/LLVM is
expected to become the primary performance compiler.

See `ROADMAP.md`, `DESIGN.md` and `BENCHMARK.md`.

## Compiler support

The source/frontend compatibility floor is DMD/Phobos 2.101. The corresponding
LDC generation is LDC 1.31.0.

Concrete compiler-package floors vary by platform because older macOS compiler
packages are not compatible with current macOS 15 runners:

| Platform | DMD | LDC |
| --- | --- | --- |
| Linux x86-64 | 2.101.2 | 1.31.0 |
| Linux ARM64 | — | 1.31.0 |
| Windows x86-64 | 2.101.2 | 1.31.0 |
| macOS x86-64 | 2.112.1 | 1.41.0 |
| macOS ARM64 | — | 1.41.0 |
| Windows ARM64 | experimental | experimental |

Current DMD and LDC releases remain part of the normal CI matrix. See
`docs/research/compiler-floor-audit.md` for the evidence and boundary tests.

## Workspace context

When developed inside `d-geospatial-workspace`, current shared architecture
and research context is available locally under:

```text
.workspace/
```

That directory is local workspace context and is not part of the `imagery-d`
repository or DUB package.

Repository-root documentation remains specific to `imagery-d`.
