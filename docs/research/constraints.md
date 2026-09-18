# R0.0 — Operational Constraints and Performance Budgets

## Status

Initial constraints for architecture research.

Numerical performance targets are provisional until representative
implementations and workloads have been benchmarked.

---

## 1. Primary workload

imagery-d is intended to become the image engine of an interactive
geospatial/OSM editor.

The engine must support both:

1. interactive imagery display and navigation;
2. analytical processing of large aerial and satellite imagery.

Interactive work has priority over background analytical work.

---

## 2. Dataset size

Dataset size must not be constrained by physical RAM.

The architecture shall support:

- individual high-resolution aerial images;
- large orthophoto mosaics;
- remote imagery composed of many provider tiles;
- multiresolution pyramids;
- datasets substantially larger than RAM;
- neighbouring imagery required for processing context.

Dataset dimensions, offsets and byte counts must not rely on avoidable
32-bit limits.

A dataset may be arbitrarily large as long as the currently required
working region can be represented and processed within the configured
resource budget.

---

## 3. Memory model

### 3.1 Memory is explicitly budgeted

The engine shall operate within a configurable memory budget.

Conceptually:

    engine_memory <= configured_memory_budget

The engine must not assume that all available system RAM belongs to it.

The editor, OSM data, renderer, operating system and other applications
must remain functional while imagery is processed.

### 3.2 Memory categories

Memory accounting should distinguish at least:

- encoded/source cache;
- decoded raster cache;
- active input regions;
- output regions;
- temporary processing workspace;
- metadata/index structures;
- future GPU resources.

### 3.3 No hidden full-image copies

Operations over large imagery must not silently materialize complete
copies of their source.

A view, ROI, channel selection or halo expansion should be zero-copy
whenever the underlying representation permits it.

Algorithms that require temporary storage must make that requirement
observable and preferably predictable.

### 3.4 Configurable budget

The exact default policy remains subject to research.

Candidate model:

    available_to_imagery =
        min(user_limit, policy_fraction_of_available_RAM)

The implementation must allow the user or host application to override
the imagery budget.

No architectural assumption may depend on a particular amount of RAM.

---

## 4. Reference memory profiles

These are test profiles, not minimum system requirements.

### Constrained

    system RAM:       8 GiB
    imagery budget:   512 MiB – 1 GiB

Purpose:

- detect accidental whole-image assumptions;
- exercise cache eviction;
- test bounded-memory behaviour.

### Typical

    system RAM:       16 GiB
    imagery budget:   2–4 GiB

Purpose:

- representative desktop editor workload.

### Performance

    system RAM:       32+ GiB
    imagery budget:   configurable, >= 4 GiB

Purpose:

- evaluate cache scaling and large analytical workloads.

All core correctness tests must remain valid under the constrained profile.

---

## 5. Region and working-set constraints

The fundamental processing unit must not be coupled to an entire dataset.

The engine shall support:

- arbitrary rectangular regions;
- neighbouring context/halo;
- regions spanning provider-tile boundaries;
- regions spanning cache-block boundaries;
- streamed production of output.

A processing request may fail explicitly when its required working set
cannot fit within the configured memory budget.

It must not silently exceed the budget by orders of magnitude.

---

## 6. Allocation constraints

Hot loops should perform no per-pixel or per-row heap allocation.

Repeated processing should reuse:

- destination buffers;
- temporary workspaces;
- decoded source blocks;
- processing context.

Benchmarks must record:

- allocation count;
- allocated bytes;
- peak temporary bytes.

An implementation that is faster only by consuming unbounded temporary
memory is not automatically preferable.

---

## 7. Interactive latency classes

Interactive editor workloads require different scheduling priorities.

### Class A — frame-sensitive

Examples:

- already-resident imagery display;
- shader/display parameter changes;
- compositing of ready imagery.

Target:

Must not depend on heavy CPU image recomputation.

### Class B — viewport-critical

Examples:

- decoding imagery entering the viewport;
- retrieving neighbouring cached tiles;
- preparing display-ready imagery.

Goal:

Visible results should appear quickly enough that navigation remains
responsive.

Exact latency targets will be derived from measurement.

### Class C — interactive background

Examples:

- quality analysis;
- local preprocessing;
- prefetch;
- construction of secondary representations.

Work must be cancellable or deprioritizable when the viewport changes.

### Class D — offline/background analysis

Examples:

- large-area image analysis;
- expensive feature extraction;
- batch benchmarks.

Throughput is more important than immediate latency.

---

## 8. Cancellation and prioritisation

The engine must eventually support cancellation.

A typical sequence is:

    viewport A requested
        ↓
    work starts
        ↓
    user pans to viewport B
        ↓
    obsolete A work is cancelled/deprioritized
        ↓
    B becomes highest priority

Long-running operations should therefore be decomposable into reasonably
bounded work units.

---

## 9. CPU performance

Performance must be measured using both throughput and memory behaviour.

Required metrics:

- elapsed time;
- MPix/s;
- effective GB/s where meaningful;
- CPU utilization;
- thread count;
- scaling efficiency;
- allocations;
- peak working set;
- temporary bytes.

Representative raster sizes shall include:

- small microbenchmark buffers;
- 2048 × 2048;
- 4096 × 4096;
- 8192 × 8192;
- streamed datasets larger than the configured imagery budget.

No universal MPix/s requirement is defined before R0 performance research.

---

## 10. Compiler targets

### Development/correctness

DMD must remain usable for development and correctness testing.

### Performance

LDC/LLVM is the primary performance compiler.

Research must compare generated code and runtime behaviour where relevant.

Compiler-specific optimisations must not leak unnecessarily into the
public API.

---

## 11. SIMD

The architecture must permit efficient SIMD execution.

Research shall evaluate:

- compiler auto-vectorization;
- contiguous versus strided input;
- planar versus interleaved data;
- alignment;
- aliasing;
- loop structure;
- explicit SIMD where auto-vectorization is insufficient.

Explicit SIMD is not a prerequisite for the initial implementation.

Correct scalar/reference paths remain required.

---

## 12. Parallelism

The engine must support multicore execution.

Parallelism should be controlled by the execution layer rather than
embedded independently in each image operation.

Research must determine:

- useful task granularity;
- memory-bandwidth saturation;
- scaling limits;
- interaction with decoding and I/O;
- oversubscription behaviour.

Thread count and worker resources must be configurable.

---

## 13. I/O separation

Network, disk, decode and processing performance must be measurable
separately.

The processing layer must not assume its source is already resident in RAM.

Potential sources include:

- in-memory buffers;
- local encoded images;
- GeoTIFF/COG;
- GDAL-backed datasets;
- XYZ/TMS;
- WMTS;
- WMS;
- cache;
- another processing operation.

---

## 14. Streaming correctness

For an operation F with finite neighbourhood requirements:

    F(whole image)[region]

must be equivalent, within a defined tolerance, to:

    F(streamed region + sufficient context)[region]

Tile, cache-block or processing-region boundaries must not create artificial
features in the output.

This invariant is a core correctness requirement.

---

## 15. Numerical tolerance

Bit-identical output is desirable where practical but not universally
required.

Each algorithm shall eventually define one of:

- exact equivalence;
- integer tolerance;
- absolute floating-point tolerance;
- relative floating-point tolerance.

Optimised, SIMD and parallel variants must be tested against a reference
implementation.

---

## 16. Safety

The public API should prefer safe D.

Performance-critical unsafe code is acceptable when justified, but it should be:

- localized;
- documented;
- covered by tests;
- hidden behind safer interfaces where practical.

The performance cost of `@safe`, bounds checks and related language features
shall be measured rather than assumed.

---

## 17. GPU

GPU processing is deferred.

However, early architecture must not require all image memory to be permanently
CPU-owned or make alternative backends impossible.

Future research must distinguish:

- display transforms;
- general-purpose GPU image processing;
- analytical compute workloads.

GPU memory will eventually require a budget separate from CPU RAM.

---

## 18. Observability

Performance and memory behaviour should be inspectable.

Future engine statistics should include, where useful:

- cache hits;
- cache misses;
- bytes fetched;
- bytes decoded;
- active regions;
- regions computed;
- work cancelled;
- memory high-water mark;
- temporary-memory high-water mark;
- timing per operation.

Observability is required both for benchmarking and for diagnosing editor
performance.

---

## 19. Initial non-goals

R0.0 does not define:

- concrete image enhancement algorithms;
- shadow correction;
- radiometric normalization;
- feature extraction;
- segmentation;
- ML models;
- final GPU API.

These are later research topics.

---

## 20. R0.0 exit criteria

R0.0 is complete when the project agrees that:

1. RAM is a configurable budget, not a dataset-size limit;
2. whole-image materialization is not a fundamental assumption;
3. regions and streaming are architectural requirements;
4. interactive and background workloads are distinct;
5. cancellation and prioritization must remain possible;
6. memory usage is benchmarked alongside execution speed;
7. no absolute throughput target is adopted without measurements;
8. correctness across region boundaries is mandatory;
9. LDC is the primary performance compiler while DMD remains supported;
10. later GPU support is not prevented by early API decisions.
