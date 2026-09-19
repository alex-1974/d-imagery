# imagery-d Design

## 1. Purpose

`imagery-d` is a high-performance image engine for large geospatial imagery.

Its first intended consumer is an interactive OpenStreetMap editor. The engine
must nevertheless remain independent of OSM-specific data structures and UI
code.

The architecture must support both interactive display workloads and later
analytical processing.

## 2. Fundamental constraints

### 2.1 RAM is a budget, not a dataset-size limit

The engine must not require an entire raster or imagery mosaic to reside in
memory.

Memory consumption must be bounded and configurable.

The working set may include:

- decoded source data;
- source/cache blocks;
- processing regions;
- temporary buffers;
- output buffers;
- metadata;
- later, GPU-resident resources.

The total dataset may be substantially larger than physical RAM.

No operation should silently require a complete-image copy.

### 2.2 Dataset dimensions

Internal coordinate and size types must not introduce avoidable 32-bit limits.

The engine must support:

- individual high-resolution images;
- imagery mosaics;
- multiresolution imagery;
- streamed datasets;
- neighbouring imagery required for context.

### 2.3 Performance

The primary use case is eventually interactive.

The architecture must therefore permit:

- prioritisation of visible data;
- cancellation of obsolete work;
- asynchronous source loading;
- prefetching;
- reuse of decoded data;
- progressive refinement;
- parallel execution.

Performance is measured rather than inferred from abstraction choice.

### 2.4 Allocation behaviour

Hot processing loops should not repeatedly allocate.

Operations should permit engine-managed or caller-managed reusable destination
and workspace storage where appropriate.

### 2.5 Correctness before optimisation

Optimised implementations require a simple reference implementation or another
clear correctness oracle.

Whole-image and streamed/region processing must produce equivalent results
within explicitly defined tolerances when sufficient neighbourhood context is
available.

## 3. Terminology

These concepts must remain distinct.

### Provider tile

A unit delivered by an external source such as XYZ, TMS or WMTS.

It is an I/O concept.

### Cache block

A unit selected by the engine for storing reusable data.

It is a storage concept.

### Region

An arbitrary rectangular area requested from an image or processing stage.

It is expected to become a fundamental processing concept, subject to R0
research.

### Window

A view into an image or region.

A window should normally avoid copying pixel data.

### Processing tile

A possible unit of scheduled work.

It must not be assumed to equal a provider tile or cache block.

### Halo / context

Input pixels outside the requested output region that are required by an
operation.

Neighbourhood requirements should eventually be expressible by the operation
rather than being globally hard-coded.

## 4. Memory and view model

The initial R0.2/R0.3 research has been completed far enough to select the
resident raster/view architecture now used by the core implementation.

The current model separates:

```text
retained physical resources
        |
        v
RasterBacking
        |
        | retained ownership
        v
RasterLease
        |
        +---- lease-bound read borrow ----> RasterView
        |
        `---- lease-bound writable borrow
                                      |
                                      v
                              WritableRasterView
                                      |
                                      | when one current plane is
                                      | flat contiguous
                                      v
                              RasterTargetPlane
```

`RasterView` remains a cheap non-owning semantic read view.

`WritableRasterView` is its package-internal writable semantic peer. It
certifies permission to write represented samples but does not imply:

```text
uniqueness
non-aliasing
contiguity
single-plane storage
thread exclusivity
```

Physical raster geometry is described using validated plane descriptors with
signed row and sample strides. Multi-plane storage does not require one common
base allocation.

Mir `ndslice` has been selected as an internal execution substrate where useful,
not as part of the public semantic API.

The current execution architecture therefore separates:

```text
imagery-d raster semantics
        |
        v
validated RasterView / WritableRasterView
        |
        v
package-internal execution classification/adapters
        |
        +-- generic strided path
        |
        `-- specialized proven fast paths
```

The public API must not expose Mir implementation types.

Ownership/lifetime and read/write capability remain separate concepts.

The lease-bound writable borrow, writable execution primitives and first
flat-contiguous `WritableRasterView -> RasterTargetPlane` execution bridge are
now implemented.

`WritableRasterView` remains package-internal while the existing operation
consumers are integrated and their eventual public contracts are reviewed.

Detailed evidence and implementation sequencing are maintained in:

```text
docs/research/memory-model.md
docs/research/raster-core-types.md
docs/architecture/raster-construction.md
docs/architecture/raster-execution.md
docs/architecture/raster-operations.md
ROADMAP.md
```

The wider image/source/cache/scheduling API remains experimental.

## 5. Region-first processing

The engine should be able to request and compute only the area actually needed.

A desired model is:

    consumer requests output region
                 ↓
        operation determines dependencies
                 ↓
        required input region + halo
                 ↓
           source/cache request

Whether this becomes a demand-driven graph, an explicit region pipeline or
another architecture will be decided during R0.

Fixed tiles must not become an accidental limitation of the processing API.

## 6. Source independence

Processing algorithms must not care whether their pixels originated from:

- an in-memory image;
- GeoTIFF;
- Cloud Optimized GeoTIFF;
- GDAL;
- XYZ/TMS;
- WMTS;
- WMS;
- a cached mosaic;
- another processing operation.

A source/backend abstraction will be researched before implementation.

## 7. CPU optimisation strategy

The engine should support both:

1. generic correctness paths for arbitrary valid views;
2. specialised fast paths for common layouts.

Likely optimisation dimensions include:

- contiguous versus strided memory;
- interleaved versus planar data;
- alignment;
- SIMD;
- cache blocking;
- multithreading;
- compile-time specialisation;
- runtime hardware dispatch where justified.

LDC/LLVM auto-vectorisation should be evaluated before explicit SIMD is used.

## 8. Parallel execution

Image algorithms should not each invent their own threading model.

Scheduling, task granularity, cancellation and priority should belong to an
engine execution layer.

The public image model should not be tied to one scheduler.

## 9. GPU boundary

GPU implementation is not an initial requirement.

The CPU architecture must, however, avoid assumptions that make future GPU
buffers or compute backends impractical.

Interactive display transforms such as:

- brightness;
- contrast;
- gamma;
- saturation;
- opacity;

should eventually be executable without rewriting entire CPU image buffers.

## 10. Geospatial concerns

Geospatial imagery requires metadata beyond ordinary image dimensions.

Future integration must account for:

- ground extent;
- geotransform;
- CRS;
- resolution/GSD;
- nodata;
- alpha/masks;
- imagery provenance;
- acquisition metadata where available.

The core image-processing representation should not require every image to be
georeferenced.

## 11. Imagery test corpus

Real imagery is required for architecture and performance testing.

The corpus must cover differences in:

- latitude;
- hemisphere;
- elevation;
- terrain;
- urban/rural environment;
- source/provider;
- effective resolution;
- image quality;
- neighbouring tiles;
- mosaic seams.

The imagery itself is not versioned.

Only scene/source definitions, download metadata, provenance and hashes are
stored in the repository.

## 12. Deferred image-processing research

Research into image enhancement and interpretation begins after the engine
foundation.

Deferred topics include:

- blur and sharpening;
- colour and exposure normalization;
- radiometric normalization;
- image-quality assessment;
- shadow detection and correction;
- feature extraction;
- segmentation;
- ML-assisted interpretation.

These topics may impose requirements on the engine, but they do not define the
initial memory architecture without evidence.
