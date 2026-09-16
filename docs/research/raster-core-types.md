# R0.3 — Raster Core Type Research

## Status

```text
R0.3 Raster Core Type Research                  ACTIVE

  RasterView semantic model                     NEXT
  Multi-plane representation                    OPEN
  ROI construction cost                         OPEN
  Descriptor lifetime                           OPEN
  Metadata size                                 OPEN
  Optimizer/codegen visibility                  OPEN
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
