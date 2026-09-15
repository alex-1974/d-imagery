# d-imagery Benchmark Principles

## Purpose

Benchmarks are part of architecture development, not an afterthought.

Every major performance-oriented design choice should be evaluated using
repeatable measurements.

## Metrics

At minimum record:

- elapsed time;
- MPix/s;
- effective GB/s where meaningful;
- allocation count;
- allocated bytes;
- temporary-memory peak;
- total working-set peak;
- thread count;
- CPU utilisation where available;
- compiler;
- compiler flags;
- CPU architecture.

## Workload classes

Benchmarks should distinguish:

### Micro

Small kernels used to understand compiler and memory behaviour.

### Region

Typical processing windows such as 2K, 4K and 8K image regions.

### Streamed

Datasets large enough that full-image processing is intentionally undesirable
or impossible under the configured memory budget.

### Interactive

Viewport-oriented workloads involving loading, cancellation, reuse and
prioritisation.

## Correctness invariant

For algorithms with finite neighbourhood requirements:

    whole-image result
        ≈
    streamed/region result with sufficient context

within defined numerical tolerances.

Tile or region boundaries must not produce artificial output discontinuities.

## Boundary tests

Test data must include:

- objects crossing provider-tile boundaries;
- roads crossing boundaries;
- buildings crossing boundaries;
- natural features crossing boundaries;
- neighbouring source tiles;
- imagery mosaic seams.

## Memory tests

Performance results without memory measurements are incomplete.

Measure separately where possible:

- source/cache memory;
- decoded raster memory;
- processing workspace;
- temporary buffers;
- outputs.

The engine must eventually support an explicit memory budget.

## Comparison policy

During R0 it is acceptable and encouraged to maintain multiple competing
implementations.

Examples:

- `mir.ndslice` versus custom stride view;
- planar versus interleaved RGB;
- generic versus contiguous kernels;
- fixed-tile versus arbitrary-region execution.

Implementations should be discarded when evidence favours a better design.

## Test imagery

Benchmark imagery is not committed to Git.

Scene and source definitions must allow the local corpus to be reproduced.

Each downloaded source should eventually have provenance information containing
at least:

- scene ID;
- source ID;
- ground extent;
- retrieval time;
- source parameters;
- dimensions;
- pixel resolution where known;
- content hash.

## Compilers

Correctness should remain testable with DMD.

Performance measurements should include LDC/LLVM and may compare DMD where
useful.
