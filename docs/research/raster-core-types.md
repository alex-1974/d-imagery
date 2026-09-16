# R0.3 — Raster Core Type Research

## Status

```text
R0.3 Raster Core Type Research                  ACTIVE

  RasterView semantic model                     ACTIVE
  Multi-plane representation                    EXPERIMENTALLY SUPPORTED
  ROI construction cost                         DONE
  Descriptor lifetime                           NEXT
  Metadata size                                 DONE
  Optimizer/codegen visibility                  DONE
  Mir adaptation                                OPEN
  Final core-type synthesis                     OPEN
```

## 1. Context

R0.2 established the following constraints:

- a logical image need not be fully resident;
- arbitrary regions are the processing primitive;
- `RasterView` is non-owning;
- ownership and lifetime live outside the view;
- retainable memory is held by a lease;
- purely borrowed memory is restricted by scope;
- planar and interleaved layouts are both first-class;
- generic strided traversal is required;
- contiguous representations require an explicit fast path;
- Mir may be used internally but must not leak into the public API;
- mutable and const views should be distinct in the type system.

R0.3 must turn those architectural constraints into concrete core-type
semantics without prematurely stabilising the public API.

## 2. Primary questions

R0.3 must answer:

1. What exactly does one `PlaneView` represent?
2. What exactly does one `RasterView` represent?
3. How are interleaved and planar channel layouts represented?
4. How are separately allocated planes represented?
5. How are arbitrary band counts represented?
6. Can ROI creation remain allocation-free?
7. Where do plane descriptors live?
8. How is their lifetime tied to `RasterLease`?
9. What metadata is needed in the hot-path view?
10. What metadata belongs only to higher-level image objects?
11. Can LDC eliminate access abstraction for the selected representation?
12. How is a view adapted internally to Mir without exposing Mir publicly?

## 3. Terminology

R0.3 distinguishes logical bands from backing allocations.

### Band

A logical image component such as:

- grayscale intensity;
- red;
- green;
- blue;
- alpha;
- near infrared;
- an arbitrary multispectral band.

### PlaneView

A non-owning two-dimensional typed view of one logical band.

Conceptually:

```text
PlaneView<T>
    data reference
    width
    height
    row stride
    sample/pixel stride
```

The exact field representation is not yet fixed.

### RasterView

A non-owning view of a raster region containing one or more logical bands.

Conceptually:

```text
RasterView<T>
    region geometry
    band/plane descriptors
    channel-layout information
```

`RasterView` does not own backing storage.

## 4. Candidate layout model

A promising representation models every logical band as an independently
strided scalar field.

### Interleaved RGB

```text
memory:

R G B R G B R G B ...

R view:
    first sample = base + 0
    sample stride = 3

G view:
    first sample = base + 1
    sample stride = 3

B view:
    first sample = base + 2
    sample stride = 3
```

### Planar RGB

```text
R R R R ...
G G G G ...
B B B B ...

R view:
    first sample = baseR
    sample stride = 1

G view:
    first sample = baseG
    sample stride = 1

B view:
    first sample = baseB
    sample stride = 1
```

This model can represent both layouts without changing the semantic type of a
band-processing kernel.

## 5. Representations to evaluate

### A. Single affine base

```text
base
rowStride
pixelStride
channelStride
```

Advantages:

- compact;
- cheap to copy;
- straightforward for one affine allocation.

Problems:

- cannot naturally represent arbitrary separately allocated bands;
- risks baking a single-allocation assumption back into the core.

### B. Fixed inline plane array

```text
PlaneView planes[N]
planeCount
```

Advantages:

- descriptors are inline;
- no second descriptor lifetime;
- no descriptor allocation.

Problems:

- introduces an arbitrary maximum band count;
- large N bloats every view;
- unsuitable as the only model for general multispectral imagery.

### C. Borrowed descriptor slice

```text
PlaneView[] planes
```

Advantages:

- arbitrary band count;
- compact top-level view;
- represents separate backing allocations naturally.

Problems:

- plane-descriptor lifetime becomes another borrow;
- careless ROI construction may allocate descriptor arrays;
- one additional indirection must be measured.

### D. Retained descriptor block

Plane descriptors are retained by the same representation/lease object that
retains backing storage.

`RasterView` borrows the descriptor block.

Advantages:

- arbitrary band count;
- descriptor lifetime naturally follows retained raster representation;
- ROI may reference existing descriptors.

Problems:

- interaction between ROI offsets and base descriptors must be designed;
- descriptor access cost must be measured.

### E. Hybrid inline + overflow

Small common band counts are stored inline; larger images use external
descriptor storage.

Advantages:

- potentially ideal RGB/RGBA common case;
- arbitrary large band count remains possible.

Problems:

- considerably more complexity;
- different code paths;
- should not be adopted without measured benefit.

## 6. Key hypothesis

The leading hypothesis is:

```text
Raster representation / lease
        |
        +-- retains backing resource(s)
        |
        +-- retains stable band descriptors
        |
        v
RasterView
        |
        +-- borrows descriptors
        +-- stores region geometry
        |
        v
PlaneView
        |
        +-- typed scalar access
        +-- row stride
        +-- sample stride
```

A region/ROI should preferably change view geometry rather than allocate and
rewrite one plane descriptor per band.

This hypothesis requires experimental validation.

## 7. Required representational capability

The selected model must represent at least:

```text
1-band contiguous
1-band padded rows
1-band ROI

RGB interleaved
RGBA interleaved

RGB planar in one allocation
RGB planar in separate allocations

arbitrary N-band planar imagery

strided ROI into all of the above
```

It should not assume that all bands share one backing allocation.

## 8. Performance questions

R0.3 will measure:

- metadata size;
- view-copy cost;
- ROI-construction cost;
- band-selection cost;
- one-band traversal;
- RGB combining traversal;
- channel-specific point operations;
- compiler visibility of strides;
- contiguous fast-path detection;
- effect of descriptor indirection.

The goal is not to optimize metadata prematurely.

The selected representation must first satisfy correctness and generality.

## 9. Safety questions

R0.3 must preserve the R0.2 lifetime model.

In particular:

- `PlaneView` is non-owning;
- `RasterView` is non-owning;
- backing resource lifetime is retained by `RasterLease`;
- descriptor lifetime must not become an unchecked second lifetime;
- views from pure borrowed foreign memory must remain scope-bound;
- normal traversal should remain `@safe`;
- trusted code must remain restricted to validated boundary construction.

## 10. Non-goals

R0.3 does not yet define:

- final public naming;
- cache implementation;
- source-provider API;
- operation graph API;
- threading model;
- GPU representation;
- format-specific decoder APIs.

## 11. Initial direction

Do not encode a universal fixed maximum number of bands into the semantic
model.

Do not require all bands to derive from one base pointer.

Do not create separate semantic raster types for planar and interleaved
storage unless measurements demonstrate that this is necessary.

Prefer a common band-oriented representation and specialize execution only
where measured performance requires it.

## R0.3 Experiment 1 and 2 findings

### Experimental representations

The first concrete experiment compared:

1. one affine RGB view carrying runtime row, pixel and channel strides;
2. a `MultiPlaneRasterView` borrowing stable per-band `PlaneDescriptor`
   metadata.

The band-oriented representation was tested with both:

- interleaved RGB represented as three stride-3 logical band streams;
- planar RGB stored in three independent allocations.

### Correctness

All generic and layout-specialized kernels produced identical grayscale
results under both DMD and LDC.

The same `MultiPlaneRasterView` kernel semantics therefore worked for both
interleaved and independently allocated planar RGB.

### Allocation-free ROI

`MultiPlaneRasterView.roi()` changes only region geometry.

The plane descriptor slice is reused unchanged:

```text
parent RasterView
      |
      +---- stable PlaneDescriptor[]
      |
      +---- ROI RasterView
```

ROI construction therefore does not allocate or rewrite one descriptor per
band.

This confirms the R0.3 hypothesis that stable descriptor metadata can be
separated from cheap per-region view geometry.

### Metadata size

On the x86-64 test platform:

```text
AffineRGBView!float                 64 bytes per view
PlaneDescriptor!float              24 bytes per band
MultiPlaneRasterView!float         48 bytes per view
three RGB plane descriptors        72 bytes stable metadata
```

The 72 bytes of RGB plane metadata are not duplicated for every ROI.

A new region view copies only the 48-byte `MultiPlaneRasterView` descriptor.

The comparison is therefore not simply 64 bytes versus 120 bytes per ROI.

### Dynamic-stride code generation

With all strides remaining runtime values, neither the affine nor the
per-band RGB-to-grayscale kernel was auto-vectorized by LDC/LLVM.

Both portable and `-mcpu=native` builds remained scalar in the hot loop.

The generic per-band kernel required more live state and register pressure,
but the representation did not uniquely lose SIMD because the affine
reference also remained scalar.

### Static layout specialization

The semantic representations were then left unchanged while execution was
specialized for known layouts:

```text
AffineRGBView:
    tightly interleaved RGB
    pixel stride = 3
    channel stride = 1

MultiPlaneRasterView:
    interleaved RGB
    sample stride = 3

MultiPlaneRasterView:
    planar
    sample stride = 1
```

With these layout facts visible to the compiler, all three specialized
kernels were vectorized by LDC/LLVM for the native AVX2 target.

This is a central R0.3 result:

> The general per-band semantic representation does not itself prevent SIMD.
> Fully runtime-variable layout prevents the compiler from selecting the best
> hot loop.

### Physical traversal remains a scheduling concern

The specialized interleaved per-band implementation deliberately traversed
R, G and B as three separate stride-3 streams.

LLVM successfully vectorized this form, but it requires more deinterleave
work than a kernel traversing one physical interleaved RGB stream.

Therefore:

```text
logical band representation
        !=
physical kernel traversal
```

A known interleaved layout should be eligible for a physical-stream
specialized kernel even when the semantic raster representation is expressed
through logical band descriptors.

### Native benchmark

Reference hardware:

```text
Intel Core i7-9750H
6 physical cores / 12 hardware threads
LDC 1.41.0 / LLVM 19.1.7
native AVX2 target
CPU 5 affinity
CPU 5 had no active SMT sibling during the reference runs
intel_pstate
maximum frequency 2.6 GHz
```

Benchmark geometry:

```text
4096 x 4096
16,777,216 pixels
24 samples
3 warmups
2 inner iterations
rotating candidate order
```

Three separate CPU-5 runs preserved the same performance ordering.

Median ranges across those runs were:

```text
dynamic affine / interleaved       29.148 .. 33.277 ms
dynamic planes / interleaved       26.611 .. 29.902 ms
static affine / interleaved        17.967 .. 19.611 ms
static planes / interleaved        19.670 .. 20.531 ms
dynamic planes / planar            22.843 .. 25.909 ms
static planes / planar             15.345 .. 16.458 ms
```

The final run was especially stable:

```text
                                        median       MPix/s
dynamic affine / interleaved            29.148        575.6
dynamic planes / interleaved            26.611        630.5
static affine / interleaved             17.967        933.8
static planes / interleaved             19.670        853.0
dynamic planes / planar                 22.843        734.4
static planes / planar                  15.345       1093.3
```

For that run:

- affine interleaved layout specialization reduced runtime by about 38%;
- plane-interleaved specialization reduced runtime by about 26%;
- planar specialization reduced runtime by about 33%;
- specialized plane-interleaved execution was about 9.5% slower than the
  specialized affine physical-stream kernel;
- specialized planar execution required about 14.6% less runtime than the
  specialized affine interleaved kernel;
- the generic plane-interleaved path was about 8.7% faster than the generic
  affine path.

Absolute timings varied somewhat between separate process runs, so these
numbers are evidence for relative behavior on the reference machine rather
than universal performance constants.

The ordering and architectural conclusion were stable.

### Interpretation

The experiment does not justify making a single affine base allocation the
core raster model.

It instead supports the following direction:

```text
MultiPlaneRasterView
        |
        | general non-owning semantic representation
        v
layout classification
        |
        +-- planar contiguous
        |       |
        |       +-- specialized planar SIMD kernel
        |
        +-- RGB interleaved
        |       |
        |       +-- specialized physical RGB SIMD kernel
        |
        +-- RGBA interleaved
        |       |
        |       +-- specialized physical RGBA SIMD kernel
        |
        +-- arbitrary strided
                |
                +-- generic fallback
```

The descriptor representation and physical execution strategy are therefore
separate architectural concerns.

### Current leading representation

The leading R0.3 direction is now:

```text
stable raster representation / lease
        |
        +-- backing resource(s)
        |
        +-- stable PlaneDescriptor[]
        |
        v
MultiPlaneRasterView
        |
        +-- borrowed descriptors
        +-- region geometry
        |
        v
layout-aware execution dispatch
```

This remains provisional until descriptor lifetime, const/mutable semantics,
Mir adaptation and trusted construction boundaries are validated.

### Next question

The next R0.3 research problem is descriptor lifetime.

Specifically:

- where stable `PlaneDescriptor` metadata lives;
- whether the descriptor block is retained directly by `RasterLease`;
- how a lease may retain multiple independent backing allocations;
- how `RasterView` safely borrows both the descriptors and their resources;
- whether ROI views remain allocation-free under the complete lifetime model.
