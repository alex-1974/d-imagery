# d-imagery

`d-imagery` is an experimental high-performance image engine written in D,
designed primarily for large geospatial imagery such as aerial photographs,
orthophotos and satellite imagery.

The initial target application is an interactive OpenStreetMap editor, but the
engine itself is intended to remain independent of OSM and generally useful for
geospatial and large-image processing.

## Status

Early research and architecture phase.

The core raster representation, ownership model, region model and execution
architecture are deliberately not stable yet.

Implementation follows measurement and architectural research rather than
preceding it.

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
