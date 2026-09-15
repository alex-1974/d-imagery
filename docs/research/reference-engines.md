# R0.1 — Reference Engine Research

## Status

Research in progress.

This document examines existing image, raster and processing engines for architectural ideas relevant to `d-imagery`.

The purpose is not to select one library to imitate. Different reference systems solve different parts of the problem well.

Image-enhancement algorithms, radiometric correction, shadow processing and feature extraction are outside the scope of R0.1.

---

## 1. Evaluation questions

Each reference implementation is evaluated against the same architectural questions.

### Data model

How are pixels, bands, dimensions, strides and ownership represented?

Can externally owned memory be wrapped without copying?

Can subregions be represented cheaply?

### Region model

Is processing based on:

- whole images;
- fixed tiles;
- arbitrary rectangular regions;
- scanline strips;
- another abstraction?

How are neighbourhood requirements represented?

### Streaming

Can datasets larger than RAM be processed?

Can an output region determine which input region is required?

Can a single non-streamable operation force full materialization?

### Memory and cache

What is cached?

Is memory consumption bounded?

Can cache memory be configured?

Are intermediate images materialized or evaluated lazily?

### Execution

How are operations scheduled?

How is work divided between threads?

Can execution strategy vary independently of algorithm semantics?

### CPU performance

How are:

- SIMD;
- vectorization;
- alignment;
- contiguous fast paths;
- arbitrary strides;

handled?

### Editor relevance

Does the architecture support:

- viewport-oriented requests;
- partial recomputation;
- cached intermediate results;
- cancellation or reprioritization;
- multiresolution preview?

### Applicability to d-imagery

For every reference distinguish:

- principles worth adopting;
- implementation details worth testing;
- concepts that should deliberately not be copied.

---

# 2. libvips

## Role

Primary reference for demand-driven large-image execution.

## Core model

libvips does not require a complete image to be resident in memory.

Its central processing abstraction is a rectangular `Region`.

A region represents a small portion of an image and may refer to:

- memory;
- a mapped file;
- another image;
- another region;
- calculated pixels.

Partial images store the means to generate requested rectangular areas instead
of necessarily storing every output pixel.

This allows long processing pipelines to remain lazy.

## Demand-driven execution

Processing is driven from a sink.

A downstream consumer requests an output area.

The pipeline then generates only the pixels necessary to satisfy that demand.

This is a strong candidate model for d-imagery:

    requested output region
             ↓
       operation dependency
             ↓
       required input region
             ↓
          source/cache

## Demand geometry

libvips operations can provide hints about their preferred access geometry.

Examples include:

- small tiles;
- wide strips.

This is important because not every algorithm has the same optimal traversal.

A geometric transform and a local convolution should not necessarily use the
same work-unit geometry.

## Threading

libvips is designed to execute pipelines concurrently rather than simply
assigning one independent image tile to each thread.

Per-thread processing state allows pixel generation to proceed with relatively
little synchronization once the pipeline has been established.

## Memory

A major design goal is retaining only the currently useful pixel working set.

Calculated pixel buffers may be cached, but intermediate full images do not
need to be materialized.

## Lessons for d-imagery

Strong candidates to adopt:

- Region as a fundamental concept;
- demand-driven region evaluation;
- operation-specific preferred traversal;
- separation between logical image and currently resident pixels;
- reusable processing state;
- long fused pipelines where advantageous.

Questions requiring experiments:

- whether full demand-driven evaluation is required from M0;
- how complex dependency propagation should be initially;
- interaction with an interactive editor scheduler.

Do not copy blindly:

- libvips-specific ownership/thread restrictions;
- its exact dimensional limits;
- implementation details tied to GLib/GObject.

---

# 3. Orfeo ToolBox / ITK pipeline model

## Role

Primary reference for streamed geospatial and remote-sensing image pipelines.

## Region taxonomy

OTB/ITK makes an important distinction between multiple regions associated with
one logical image.

### LargestPossibleRegion

The complete logical dataset extent.

### BufferedRegion

The part currently resident in memory.

### RequestedRegion

The part a downstream consumer requires.

This distinction maps closely onto the problem d-imagery must solve.

A logical image must not be confused with its resident working set.

## Requested-region propagation

A downstream output request propagates upstream.

Each operation determines which input region is required to produce the
requested output.

This permits large processing pipelines to operate on datasets much larger than
RAM.

## Neighbourhood processing

Operations that require neighbouring pixels expand their requested input
region.

Conceptually:

    output region
         ↓
    dependency radius
         ↓
    expanded input region

This is a more general model than attaching a fixed halo to every processing
tile.

The halo should therefore probably be a consequence of an operation's
dependency rather than a property of imagery itself.

## Streaming correctness

OTB explicitly distinguishes streaming from threading.

Streaming means that independently processed portions of a large image combine
to produce the same result as processing the complete image.

This directly supports a central d-imagery invariant:

    F(whole image)[R]
        ≈
    F(streamed with sufficient context)[R]

## Pipeline property

Streamability is a property of the complete pipeline.

One operation that requires the entire dataset can cause a pipeline to lose its
bounded-memory streaming behaviour.

This must be visible in d-imagery rather than occurring accidentally.

## Memory estimation

OTB can propagate a requested region and estimate the RAM required to process
it.

This is particularly relevant to the explicit memory-budget requirement in
d-imagery.

## Lessons for d-imagery

Strong candidates to adopt:

- logical extent versus resident extent;
- requested regions;
- upstream dependency propagation;
- neighbourhood expansion derived from an operation;
- streamability as an observable pipeline property;
- estimating working-set requirements before execution.

This may be the strongest architectural reference for the Region/Window/Halo
design.

---

# 4. Halide

## Role

Primary reference for separating algorithm semantics from execution strategy.

## Algorithm versus schedule

Halide defines what is computed separately from how computation is executed.

Scheduling decisions can include:

- loop splitting;
- loop reordering;
- tiling;
- vectorization;
- unrolling;
- parallelization;
- producer placement;
- temporary-storage placement.

Changing a schedule is intended not to change the semantic result.

## Relevance to d-imagery

A d-imagery operation should not unnecessarily encode assumptions such as:

    tile size = 512
    thread count = 8
    vector width = 8
    planar layout required

inside its mathematical definition.

A conceptual separation should exist between:

    operation semantics

and:

    execution policy

This does not imply that d-imagery needs a Halide-like DSL.

## Performance lesson

Halide's scheduling material emphasizes trade-offs between:

- locality;
- temporary memory;
- redundant computation;
- parallelism.

These trade-offs are difficult to predict analytically.

They should be benchmarked.

This strongly supports the R0 prototype bake-off.

## Lessons for d-imagery

Adopt as principles:

- algorithm semantics independent of scheduling where practical;
- empirical schedule evaluation;
- explicit locality versus recomputation trade-offs;
- vectorization and parallelism as execution concerns.

Research later whether a lightweight internal execution-policy system is
sufficient.

Do not attempt to implement a Halide-style compiler or scheduling language
without evidence that it is required.

---

# 5. GDAL

## Role

Primary reference and probable backend for geospatial raster I/O.

GDAL should generally be integrated rather than reimplemented.

## Block-based I/O

Raster drivers expose blocks appropriate to their underlying storage.

Physical source block geometry must therefore remain distinct from d-imagery's
logical processing regions.

This reinforces the distinction:

    source block
        !=
    cache block
        !=
    processing region

## RasterIO

Windowed raster access permits selected portions of a dataset to be read rather
than requiring whole-image decoding.

Drivers may provide specialized RasterIO implementations.

## Raster block cache

GDAL maintains a configurable raster block cache.

The cache has an explicit memory limit and evicts blocks as required.

This is directly relevant to d-imagery's memory-budget model.

## Virtual memory

GDAL also supports virtual-memory representations where backing dataset content
is populated as memory pages are accessed.

This demonstrates another possible source/backend strategy for large rasters.

## Lessons for d-imagery

Adopt:

- explicit source abstraction;
- source-native blocks hidden behind region access;
- configurable cache budgets;
- independent I/O and processing measurements.

Avoid:

- coupling the processing core directly to GDAL objects;
- treating GDAL's block cache as the complete d-imagery cache architecture.

Source caching and processed-result caching solve different problems.

---

# 6. OpenCV

## Role

Reference for lightweight image views, external-memory wrapping and optimized
CPU kernels.

## cv::Mat model

`cv::Mat` combines a relatively small metadata header with pixel storage.

A matrix may wrap externally owned data.

The row step/stride can be supplied explicitly.

ROI/submatrix construction creates a new header referring to the existing pixel
storage rather than copying the pixels.

This is highly relevant to the proposed `RasterView` / `ImageView` design.

## External memory

OpenCV demonstrates the usefulness of allowing an image view to wrap memory
owned elsewhere.

Potential d-imagery producers include:

- decoders;
- GDAL;
- mapped files;
- cache blocks;
- externally allocated buffers;
- later GPU staging buffers.

## Continuity and fast paths

A submatrix or externally supplied image may be strided rather than tightly
packed.

Algorithms can distinguish contiguous layouts from generic layouts and use
faster paths where appropriate.

This supports the planned d-imagery distinction between:

    generic valid view

and:

    specialized contiguous fast path

## SIMD

OpenCV's Universal Intrinsics layer abstracts architecture-specific SIMD and
vector-length differences.

d-imagery should first evaluate LLVM auto-vectorization, but OpenCV provides a
useful design reference if explicit portable SIMD becomes necessary.

## Lessons for d-imagery

Adopt as principles:

- cheap image headers/views;
- explicit strides;
- external-memory wrapping;
- zero-copy ROI;
- optimized contiguous paths without rejecting strided input.

Do not assume OpenCV's image model is sufficient for large-image streaming or
geospatial execution.

---

# 7. GEGL

## Role

Primary reference for future interactive non-destructive editor processing.

## Processing graph

GEGL models image processing as a graph.

It supports processing of subregions and their dependencies rather than
necessarily evaluating complete images.

## Cache

Intermediate subgraph results can be cached to accelerate repeated rendering.

This is highly relevant to an editor where the same imagery may repeatedly be
displayed while only a small parameter or viewport changes.

## Large buffers

GEGL supports image buffers larger than RAM and tiled backing storage.

It can also use external tile backends.

## Multiresolution preview

GEGL supports mipmap-oriented preview processing.

This is relevant to editor zoom levels:

    zoomed far out
        → lower-resolution work

    zoomed in
        → full-resolution regions

The engine should not process full-resolution source pixels unnecessarily for a
small on-screen representation.

## Lessons for d-imagery

Potential later concepts:

- graph evaluation;
- subgraph caches;
- invalidation;
- mipmap-aware execution;
- reusable intermediate results;
- editor-oriented partial recomputation.

These concepts are important but probably belong after the initial Region and
memory architecture.

---

# 8. mir.ndslice

## Role

Primary D-native candidate for low-level multidimensional views.

## Capabilities

`mir.ndslice` provides multidimensional slices with shape and layout semantics.

It supports view operations such as:

- slicing;
- transposition;
- channel/subdimension access;
- lazy mapped expressions.

Many such operations can create views without copying the underlying storage.

Element-wise expression chains can be evaluated into a destination without
requiring intermediate materialization in common cases.

## Relevance

This potentially solves a substantial portion of:

- shape;
- strides;
- ROI;
- channel views;
- non-owning raster views;
- generic multidimensional iteration.

## Risks to evaluate

Generality may impose costs in image hot paths.

Research must determine:

- generated code quality;
- bounds-check behaviour;
- alias analysis;
- auto-vectorization;
- contiguous specialization;
- interaction with `@safe`;
- representation size;
- ease of wrapping external storage;
- ergonomics for interleaved versus planar images.

## Architectural rule

Even if selected internally, `mir.ndslice` should not automatically become the
public semantic image API.

A likely layering remains:

    mir.ndslice or equivalent
              ↓
          RasterView
              ↓
           ImageView
              ↓
       geospatial metadata

This leaves room for optimized kernels or future storage backends to bypass the
generic view implementation where justified.

---

# 9. DCV

## Role

D-native reference for actual image processing built on `mir.ndslice`.

DCV is especially useful because it demonstrates that ndslice can be used as
the basis of a practical image-processing API rather than only numerical-array
code.

## Model

DCV uses Mir `Slice` extensively for image manipulation.

Examples include:

- images represented as multidimensional slices;
- selecting one channel through slicing;
- conversion between numeric types;
- convolution;
- colour conversion;
- image display.

This provides useful prior art for the d-imagery R0.2 prototype.

## Research value

Inspect DCV specifically for:

- `Image` ownership;
- conversion between `Image` and `Slice`;
- channel ordering;
- allocation policy;
- convolution implementation;
- `@nogc` use;
- use of DMD versus LDC;
- areas where arbitrary slice generality complicates performance.

## Caution

DCV solves computer-vision/image-processing problems rather than large
geospatial streaming.

It should therefore be used primarily as a D implementation reference, not as
the overall d-imagery architecture.

---

# 10. Comparative architecture

| Concern | Strongest reference |
|---|---|
| Large-image demand evaluation | libvips |
| Requested-region propagation | OTB/ITK |
| Halo/dependency derivation | OTB/ITK |
| Algorithm/schedule separation | Halide |
| Geospatial raster I/O | GDAL |
| Explicit cache budget | GDAL / libvips |
| Cheap strided image views | OpenCV / mir.ndslice |
| SIMD abstraction | OpenCV |
| D-native multidimensional views | mir.ndslice |
| D-native image processing | DCV |
| Editor processing graph | GEGL |
| Multiresolution editor preview | GEGL |

No single reference provides the complete desired architecture.

---

# 11. Preliminary synthesis for d-imagery

R0.1 currently suggests the following conceptual separation:

    LogicalImage
         │
         ├── metadata / full extent
         │
         ▼
    Region request
         │
         ▼
    Operation dependency
         │
         ▼
    Required input region
         │
         ▼
    Source / cache
         │
         ▼
    resident RasterView
         │
         ▼
    execution policy
       /    |    \
    scalar SIMD parallel

The important distinction is:

    ProviderTile != CacheBlock != Region != ProcessingTask

A tile is not currently considered a suitable universal abstraction.

`Region` is the leading candidate for the logical processing abstraction.

`RasterView` is the leading candidate for the resident-memory abstraction.

`mir.ndslice` is a leading candidate for implementing `RasterView`, but this
remains an empirical R0.2 question.

---

# 12. Architectural hypotheses to test

The following are hypotheses, not decisions.

### H1

Arbitrary rectangular `Region` requests are a better fundamental abstraction
than fixed processing tiles.

### H2

Neighbourhood context should be derived from operation dependencies rather than
stored as a fixed halo property.

### H3

Logical image extent and resident pixel storage must be separate concepts.

### H4

A small strided view abstraction is sufficient for the majority of CPU
algorithms.

### H5

`mir.ndslice` can provide that view abstraction without material loss of
performance compared with a custom representation.

### H6

Common contiguous layouts require specialized fast paths even if arbitrary
strides are supported by the generic API.

### H7

Processing semantics and execution policy should remain separable.

### H8

Source caching and processed-result caching should be distinct systems.

### H9

The future editor should request imagery by viewport/region rather than directly
driving provider tiles.

### H10

Memory requirements for an operation should become estimable before executing a
large region.

---

# 13. R0.1 output

R0.1 should produce inputs for later ADRs, but should not prematurely create
those ADRs.

The next research phase must test the most consequential hypotheses:

- `mir.ndslice` versus custom stride views;
- interleaved versus planar storage;
- contiguous versus arbitrary-stride hot loops;
- region and halo representation.

These experiments belong to R0.2.