# imagery-d Roadmap

## Current implementation checkpoint — 2026-09-19

The repository has progressed beyond the initial architecture-only stage while
the long-term milestone structure below remains valid.

Current core status:

- retained resource ownership and raster backing are implemented;
- `RasterView` provides the read-only semantic resident view;
- signed-stride and multi-plane backing validation are implemented;
- execution layouts and Mir adapters remain internal;
- scalar reduction/copy kernels and measured specializations exist internally;
- `ubyte -> float` conversion has a checked internal dispatch path;
- per-resource `readOnly` / `readWrite` provenance is retained;
- writable backing certification is implemented;
- package-internal `WritableRasterView` with writable ROI, sample read and
  sample write semantics is implemented and DIP1000-tested with DMD and LDC;
- `RasterLease` can derive a package-internal lease-bound writable borrow from
  retained `readWrite` resources, while const leases and escaping borrows are
  rejected by the DIP1000 lifetime model;
- `WritableRasterView` now exposes the minimal package-internal execution
  primitives required by the existing contiguous writable-target consumers:
  shared plane-layout classification and a lifetime-bound mutable region-origin
  execution pointer;
- flat-contiguous planes of a certified `WritableRasterView` can now derive the
  existing package-internal `RasterTargetPlane` capability while preserving
  DIP1000 lifetime provenance through the target and existing Mir adapters.

The current raster-operations sequence is:

```text
E5.4a    public-surface audit                         complete
E5.4b    writable prerequisites audit                 complete
E5.4c    retained write-access provenance design      complete
E5.4c.1  retained ResourceAccess implementation       complete
E5.4d    semantic writable-view contract              complete
E5.4d.1a writable backing certification               complete
E5.4d.1b semantic WritableRasterView implementation   complete
E5.4d.1c RasterLease -> writable borrow                complete
E5.4e    writable execution capabilities              in progress
E5.4e.1  writable execution primitives                complete
E5.4e.2  WritableRasterView -> RasterTargetPlane       complete
E5.4e.3  existing consumer integration                next
E5.4f    public operation contract redesign            not started
E5.4g    stable public operation exposure              not started
```

`WritableRasterView` is intentionally still package-internal. It establishes
write permission but does not imply uniqueness, non-aliasing, contiguity or
thread exclusivity.

The resident raster/view core now includes both read-only and writable
lease-bound lifetime integration plus the first contiguous writable execution
bridge. Remaining work before API stabilization is primarily integration of
that bridge into the existing copy/conversion consumers and the public
operation-contract design.

M2 has partial internal implementation used to validate the engine
architecture; copy, reduction and conversion machinery are not yet exposed as
stable public raster operations.

At this checkpoint, the coordinated repository/worktree rename had not yet been
performed: the repository and DUB package still used the historical `d-imagery`
name. The reorganization on 2026-09-18 subsequently renamed the project and DUB
package to `imagery-d`.

## R0 — Constraints, Research and Architecture

The first phase determines the architecture before the core API is stabilized.

### R0.0 — Operational constraints

Define measurable limits and workload classes for:

- RAM;
- cache memory;
- temporary memory;
- dataset dimensions;
- allocations;
- I/O;
- CPU throughput;
- interactive latency;
- concurrency;
- cancellation;
- numerical correctness;
- portability.

Establish benchmark metrics before optimising implementation.

Deliverable:

    docs/research/constraints.md

### R0.1 — Reference architecture research

Study architecture and implementation strategies used by:

- libvips;
- Halide;
- GDAL;
- Orfeo ToolBox;
- OpenCV;
- GEGL;
- Mir / `mir.ndslice`.

Focus on:

- views and strides;
- ownership;
- regions/windows;
- streaming;
- requested-region propagation;
- caching;
- tiling;
- SIMD;
- scheduling;
- large-image processing.

Deliverable:

    docs/research/reference-engines.md

### R0.2 — Memory-model research

Compare experimentally:

- custom pointer/shape/stride views;
- `mir.ndslice`;
- packed pixel types;
- planar layout;
- interleaved layout;
- HWC and CHW;
- aligned allocation;
- arbitrary-stride views;
- externally owned buffers.

Prototype:

- raster;
- ROI;
- channel view;
- non-contiguous view;
- expanded region/halo.

Deliverable:

    docs/research/memory-model.md

### R0.3 — Region, tile and streaming model

Define and separate:

- provider tiles;
- cache blocks;
- regions;
- windows;
- processing tiles;
- halo/context;
- output regions.

Compare fixed-tile processing with arbitrary requested regions.

Test neighbouring tiles and cross-boundary processing.

Deliverable:

    docs/research/regions-streaming.md

### R0.4 — Execution and scheduling research

Research:

- synchronous baseline execution;
- region-level tasks;
- worker pools;
- pipeline parallelism;
- work stealing;
- I/O/decode/compute separation;
- priority;
- cancellation;
- prefetch.

Deliverable:

    docs/research/execution.md

### R0.5 — CPU and SIMD research

Use deliberately simple kernels:

- copy;
- fill;
- RGB channel extraction;
- RGB to grayscale;
- point transform;
- LUT;
- min/max reduction;
- histogram;
- small convolution.

Compare:

- DMD;
- LDC;
- generic strided loops;
- contiguous specialised loops;
- LLVM auto-vectorisation;
- explicit SIMD where justified;
- single-threaded and parallel execution.

Deliverable:

    docs/research/cpu-performance.md

### R0.6 — I/O and raster-source architecture

Research boundaries for:

- GDAL;
- local codecs;
- GeoTIFF;
- COG;
- XYZ/TMS;
- WMTS;
- WMS.

Define requirements for a generic raster/imagery source abstraction.

Deliverable:

    docs/research/io-sources.md

### R0.7 — Reproducible imagery corpus

Define test scenes covering:

- multiple latitudes;
- Northern and Southern Hemisphere;
- low and high elevation;
- flat and mountainous terrain;
- urban and rural areas;
- multiple providers;
- multiple quality levels;
- neighbouring tiles;
- mosaic seams.

Imagery is downloaded locally and is not committed.

Version:

- scene definitions;
- source definitions;
- retrieval parameters;
- provenance;
- hashes.

Deliverable:

    docs/research/test-corpus.md
    benchmark/scenes/
    benchmark/sources/

### R0.8 — Prototype bake-off

Implement disposable competing prototypes.

At minimum compare:

- `mir.ndslice` versus custom views;
- planar versus interleaved layouts;
- fixed tiles versus arbitrary regions;
- generic versus contiguous fast paths;
- whole-image versus streamed execution;
- sequential versus parallel processing.

Production compatibility is not required.

### R0.9 — Architecture synthesis

Consolidate the research into:

- terminology;
- ownership model;
- raster/view representation;
- region/window API;
- dependency/halo model;
- cache model;
- source model;
- execution model;
- CPU fast-path strategy;
- GPU boundary.

Update `DESIGN.md` and record major decisions as ADRs.

### R0 exit criteria

R0 is complete when:

1. reference engines have been studied;
2. operational constraints are documented;
3. representative imagery is reproducibly obtainable;
4. memory-layout alternatives have been benchmarked;
5. Region/Tile/Halo semantics are defined;
6. streaming correctness rules are defined;
7. CPU performance behaviour has been measured;
8. `mir.ndslice` has been evaluated experimentally;
9. major architecture choices have ADRs.

---

## M0 — Core Raster and View Model

Implement the architecture selected during R0.

Initial focus:

- storage ownership;
- raster shape;
- strides;
- views;
- regions/windows;
- pixel/band representation;
- correctness tests.

---

## M1 — Regions, Streaming and Cache

Implement:

- requested regions;
- halo/context propagation;
- cache blocks;
- bounded memory;
- neighbouring source access;
- streamed processing;
- whole-image/streamed equivalence tests.

---

## M2 — Fundamental Processing Primitives

Implement only the operations required to validate the engine:

- copy/fill;
- conversions;
- point transforms;
- simple reductions;
- basic neighbourhood kernels.

---

## M3 — CPU Performance

Optimise proven hot paths using:

- LDC/LLVM;
- SIMD-friendly loops;
- layout specialisation;
- multithreading;
- reusable workspaces.

---

## M4 — Image I/O and Geospatial Sources

Integrate source backends and geospatial metadata.

---

## R1 — Image Processing Research

Only after the engine foundation is stable, research:

- resampling;
- sharpening and blur;
- local contrast;
- colour processing;
- quality metrics;
- radiometric normalization.

---

## R2 — Illumination and Shadow Research

Research:

- cast shadows;
- terrain shadows;
- vegetation shadows;
- sun direction;
- acquisition metadata;
- shadow confidence;
- illumination correction.

---

## M5+ — Advanced Processing

Later milestones may include:

- editor display pipelines;
- GPU processing;
- feature extraction;
- segmentation;
- ML inference;
- mapping assistance.
