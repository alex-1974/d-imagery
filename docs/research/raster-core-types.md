# R0.3 — Raster Core Type Research

## Status

```text
R0.3 Raster Core Type Research                  DONE

  RasterView semantic model                     DONE
  Multi-plane representation                    DONE
  ROI construction cost                         DONE
  Descriptor lifetime                           DONE
  Metadata size                                 DONE
  Optimizer/codegen visibility                  DONE
  Mir adaptation                                DONE
  Mutability capability model                   DONE
  Final core-type synthesis                     DONE
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

### Descriptor lifetime experiment

The descriptor lifetime model was tested with a retained representation that
owns:

- multiple physically independent backing allocations;
- a stable `PlaneDescriptor[]` block;
- release metadata for every backing resource.

The experimental ownership chain is:

```text
RasterBacking
    |
    +-- ResourceEntry[]
    |       |
    |       +-- backing allocation 0
    |       +-- backing allocation 1
    |       +-- ...
    |
    +-- stable PlaneDescriptor[]
             |
             v
       SafeRefCounted
             |
             v
        RasterLease
             |
             | borrow
             v
        RasterView
             |
             | return scope
             v
            ROI
```

The concrete use of `SafeRefCounted` remains an implementation experiment,
not a required public API semantic.

#### Positive lifetime results

Both DMD and LDC validated that:

- three independent plane allocations may be retained by one representation;
- the descriptor block remains alive with those resources;
- a `RasterView` can borrow that stable descriptor block;
- copying `RasterLease` retains the entire representation;
- destroying an intermediate lease does not free the resources;
- destroying the final lease releases every independent resource exactly once;
- ROI creation reuses the same descriptor block;
- a lease-bound ROI can be used from `@safe` code;
- nested ROI transformations remain valid inside the lease lifetime.

No descriptor allocation or reconstruction is required by ROI construction.

#### DIP1000 escape protection

Negative compile-time probes were evaluated with both DMD and LDC using
`-preview=dip1000`.

Both compilers rejected:

```text
return RasterView past local RasterLease
return ROI past local RasterLease
return nested ROI past local RasterLease
assign RasterView to longer-lived outer local
assign RasterView to global state
assign RasterView into independently living heap object
```

The direct view return is diagnosed as an escape from the local lease.

For ROI transformation, `MultiPlaneRasterView.roi()` and
`AffineRGBView.roi()` use `return scope`, preserving the alias provenance of
the source view.

The resulting behavior is:

```text
lease.view()
    |
    +-- safe use within lease              PASS
    |
    +-- return beyond lease                REJECT

lease.view().roi(...)
    |
    +-- safe use within lease              PASS
    |
    +-- return beyond lease                REJECT

lease.view().roi(...).roi(...)
    |
    +-- safe use within lease              PASS
    |
    +-- return beyond lease                REJECT
```

For nested ROI escape, both compilers diagnose the returned ROI as derived
from a scope variable.

This demonstrates transitive lifetime propagation through repeated
allocation-free ROI transformations.

#### R0.3 lifetime conclusion

The experiment supports the following design direction:

> `RasterView` remains fully non-owning. Stable plane descriptors and every
> resource referenced by them are retained by an owning representation behind
> `RasterLease`. DIP1000 ties views and derived ROIs to that lease.

A lease is therefore not synonymous with one allocation.

It may retain:

- one contiguous allocation;
- multiple planar allocations;
- decoder-owned resources;
- mapped storage;
- cache blocks;
- or another composite retained representation.

The trusted construction boundary remains responsible for validating that
every descriptor refers to storage retained by the same representation.

### Mir adaptation experiment

The R0.3 experiments validate Mir as an internal execution substrate without
making Mir types part of the imagery-d raster semantic model.

The boundary is:

```text
MultiPlaneRasterView
        |
        | imagery-d semantics
        v
internal Mir adapter
        |
        +-- Universal 2D
        +-- Canonical 2D
        +-- Contiguous 2D
        +-- Contiguous 1D fast path
        |
        v
kernel implementation
```

`PlaneDescriptor` therefore remains imagery-d metadata. An `ndslice` is an
ephemeral execution view constructed from an already validated
`RasterView`.

#### Representation mapping

The tested mapping is:

```text
arbitrary row/sample stride
    -> Slice!(T*, 2, Universal)

sampleStride == 1
    -> Slice!(T*, 2, Canonical)

sampleStride == 1
and rowStride == logical width
    -> Slice!(T*, 2, Contiguous)

fully contiguous and operation is linearizable
    -> Slice!(T*, 1, Contiguous)
```

This distinction is important for ROI.

A narrow ROI cut from a physically contiguous full image remains unit-stride
in x, but its physical row stride is still the full source row width.

Such a view is:

```text
Canonical
not Contiguous
```

The adapter therefore does not infer full contiguity merely from
`sampleStride == 1`.

All tested mappings are O(1) and allocate no pixel or descriptor storage.

#### Lifetime preservation

Mir adaptation preserves the existing lease lifetime relation.

Both DMD and LDC accept a Mir slice used while its originating `RasterLease`
is alive.

Both reject returning the adapted slice beyond that lease lifetime.

The chain therefore remains:

```text
RasterLease
    |
    v
RasterView
    |
    | return scope
    v
Mir Slice
```

Mir does not provide an escape hatch around the DIP1000 lifetime boundary.

#### Code-generation results

LDC 1.41 / LLVM 19.1.7 with native AVX2 was used for the code-generation
probe.

The same in-place float gain/bias operation was compiled for the different
slice kinds.

Observed instruction counts:

```text
Universal 2D              134
Canonical 2D               57
Contiguous 2D              57
Contiguous 1D              37
raw pointer 1D baseline    39
```

`Universal` still vectorized when the runtime sample stride happened to be
one.

LLVM generated a runtime layout/versioning check before entering its AVX2
unit-stride fast path.

The general representation therefore does not imply permanently scalar
execution, but it carries substantially more dispatch/control code.

`Canonical` eliminates that runtime sample-stride decision. It produced a
direct row-wise AVX2 loop.

For the tested nested 2D kernel, `Canonical` and `Contiguous` produced
essentially equivalent vector loops. Merely changing the slice kind to
`Contiguous` did not remove the row loop.

#### Linear contiguous fast path

A fully contiguous region can instead be adapted explicitly to a
one-dimensional `Contiguous` Mir slice when the operation is semantically
linearizable.

The resulting kernel produced:

```text
Mir Contiguous 1D     37 instructions
raw pointer baseline  39 instructions
```

Both used the same four-wide-block AVX2 loop structure:

```text
4 x YMM loads
4 x vmulps
4 x vaddps
4 x YMM stores
```

followed by the same scalar tail strategy.

This is strong evidence that the internal Mir representation can provide a
zero-cost abstraction for the contiguous linear fast path on the tested
compiler/toolchain.

The slight instruction-count difference between the Mir and raw-pointer
versions is in loop/exit bookkeeping, not in the vector hot loop.

#### Execution implication

The experiments support classification once before entering a hot kernel:

```text
RasterView
    |
    v
layout classifier
    |
    +-- arbitrary stride
    |       -> Universal kernel
    |
    +-- unit x stride
    |       -> Canonical row kernel
    |
    +-- fully contiguous, 2D semantics required
    |       -> Contiguous 2D kernel
    |
    +-- fully contiguous, linearizable operation
            -> Contiguous 1D kernel
```

Physical execution representation is therefore a scheduling concern, not a
reason to weaken the general `RasterView` semantic model.

#### Remaining implementation invariant

Linear adaptation computes the logical element count as:

```text
width * height
```

The final trusted construction/classification layer must guarantee that this
product and all stride/offset arithmetic are representable without overflow.

R0.3 keeps this requirement explicit through the flat-adaptation predicate;
the final core types must make it part of the validated view invariants.

#### R0.3 Mir conclusion

The experiments support Mir as an internal substrate.

They do not support exposing Mir types in the public imagery-d API.

The preferred relationship is:

```text
public/internal imagery-d raster semantics
        |
        v
validated RasterView
        |
        v
small internal Mir adapter
        |
        v
layout-specialized kernel
```

The adapter is allocation-free and can retain the optimizer visibility
needed for efficient AVX2 execution.

The contiguous one-dimensional path is effectively equivalent to the tested
raw-pointer implementation.

### Final core-type synthesis

R0.3 selects a provisional core type architecture for imagery-d.

The purpose of this synthesis is not to freeze the final public API.

It establishes the semantic boundaries that subsequent implementation work
should preserve unless later experiments provide contrary evidence.

The selected decomposition is:

```text
logical image / retained representation
        |
        +-- backing resource(s)
        +-- stable plane descriptors
        +-- validated storage metadata
        +-- storage access capability
        |
        v
      lease
        |
        v
   RasterView
        |
        v
execution classification
        |
        +-- generic strided
        +-- canonical unit-X
        +-- contiguous 2D
        +-- contiguous 1D
```

The central R0.3 conclusion is that four concerns must remain separate:

```text
physical description
lifetime ownership
pixel access capability
execution representation
```

No single type should encode all four.

#### Region geometry

The provisional region value type is:

```d
struct Region2D
{
    size_t x;
    size_t y;
    size_t width;
    size_t height;
}
```

`x` and `y` are coordinates relative to the logical origin represented by
the retained plane descriptors.

A `RasterView` therefore represents:

```text
stable descriptor block
+
Region2D
```

ROI creation changes only `Region2D`.

It does not rebuild or copy plane descriptors.

Repeated ROI transforms preserve the same descriptor block and accumulate
the logical origin.

The experiments validated this behavior transitively.

Empty regions are not inherently forbidden by the model.

Construction and execution code must nevertheless avoid invalid pointer
formation or dereference for empty views.

#### Plane descriptor

The provisional physical plane descriptor is:

```d
struct PlaneDescriptor
{
    const(void)* base;
    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;
}
```

`base` identifies logical sample `(0, 0)` for the plane represented by the
descriptor.

The two strides are signed because the general representation should not
require positive physical traversal.

Stride units are elements of the typed sample `T`, not bytes.

This is deliberate.

The raster layer works in sample coordinates, while the backing-resource
layer works in byte extents.

External byte-stride formats must therefore be validated and converted once
at the trusted import/construction boundary.

The descriptor is access-neutral.

In particular:

```text
const(void)* base
```

does not assert that the underlying storage is physically immutable.

It means that the descriptor itself does not grant write authority.

A writable typed pointer may only be produced through the validated writable
view path.

The descriptor block becomes stable after validated publication.

Views borrow it but do not own it.

#### Logical band model

Descriptor order is logical band order.

The representation supports arbitrary positive band counts rather than
embedding RGB or RGBA directly in the core type.

Examples:

```text
planar RGB

plane 0:
    allocation R
    sampleStride = 1

plane 1:
    allocation G
    sampleStride = 1

plane 2:
    allocation B
    sampleStride = 1
```

and:

```text
interleaved RGB

plane 0:
    base = pixel stream + red offset
    sampleStride = physical pixel stride

plane 1:
    base = pixel stream + green offset
    sampleStride = physical pixel stride

plane 2:
    base = pixel stream + blue offset
    sampleStride = physical pixel stride
```

The semantic representation therefore does not require separate core types
for planar and interleaved images.

However, storage topology remains explicit at the retained representation /
execution-planning level.

At minimum the planner must distinguish:

```text
planar
pixel-interleaved
arbitrary/custom
```

This metadata must not be confused with execution layout classification.

Storage topology describes relationships among bands.

Execution classification describes how one current region can be traversed.

#### Read-only view

The selected read capability is conceptually:

```d
struct RasterView(T)
{
private:
    const(PlaneDescriptor)[] planes_;
    Region2D region_;
}
```

Pixel access yields:

```d
const(T)*
```

or an equivalent read-only reference.

The view:

- owns no pixel storage;
- owns no descriptor storage;
- retains no resources by itself;
- may be copied cheaply;
- remains lifetime-bound to its originating lease/backing;
- preserves that lifetime through ROI and adapter transformations.

With the provisional fields above, the expected x86-64 payload remains the
same fundamental shape as the experimentally measured 48-byte multi-plane
view:

```text
descriptor slice     16 bytes
Region2D             32 bytes
                     --------
                     48 bytes
```

This size observation is not an ABI promise.

#### Writable view

Writable access is represented by a distinct capability type:

```d
struct MutableRasterView(T)
{
private:
    const(PlaneDescriptor)[] planes_;
    Region2D region_;
}
```

Its typed pixel access yields:

```d
T*
```

The experiments validated:

```text
MutableRasterView!T
    -> writable pixel access

MutableRasterView!T.roi(...)
    -> MutableRasterView!T

MutableRasterView!T.readOnly()
    -> RasterView!T

RasterView!T.roi(...)
    -> RasterView!T

RasterView!T pixel write
    -> compile-time rejection

RasterView!T
    -> MutableRasterView!T
    -> no implicit conversion
```

Mutable-to-read-only downgrade is O(1).

The same stable descriptor block is reused.

No reverse safe capability conversion exists.

The `const(void)*` stored by `PlaneDescriptor` therefore acts as a useful
capability boundary: raw physical metadata alone cannot create writable
access in `@safe` code.

A small trusted implementation boundary may cast that address back to `T*`
only after writable backing storage has been validated.

#### Lifetime capability

Pixel-access capability and lifetime ownership remain separate.

The conceptual ownership model is:

```text
RasterBacking
        |
        +-- resource 0
        +-- resource 1
        +-- ...
        +-- stable PlaneDescriptor[]
        +-- validated storage metadata
        |
        v
retained owner
        |
        +--------------------------+
        |                          |
        v                          v
RasterLease!T             MutableRasterLease!T
        |                          |
        v                          v
RasterView!T              MutableRasterView!T
```

The exact retained-owner implementation is not part of the semantic API.

`SafeRefCounted` was sufficient for the experiments but remains an
implementation option rather than a required public type.

A lease may retain:

- one contiguous allocation;
- multiple planar allocations;
- mapped storage;
- decoder-owned buffers;
- cache blocks;
- or composite resources.

The lease is therefore not equivalent to one allocation.

Copying a lease extends the retained representation lifetime.

Views do not.

A mutable lease may expose read-only capability without copying the retained
resources.

Whether the final API materializes that downgrade as a separate
`RasterLease!T`, as another lightweight wrapper, or only as a read-only view
is an implementation/API refinement rather than an R0.3 semantic question.

#### Mutable capability is not exclusivity

`MutableRasterView` means:

```text
the referenced storage may be written
```

It does not mean:

```text
this is the only writable reference to the storage
```

D does not provide Rust-style unique borrowing through this model.

Therefore:

```text
lifetime safety
write permission
thread safety
alias control
synchronization
```

remain distinct concerns.

Parallel execution must establish any additional non-aliasing or
synchronization preconditions it requires.

#### Trusted construction boundary

Public or ordinary `@safe` code must not freely construct arbitrary validated
views from raw pointers.

A small trusted construction boundary is responsible for proving the
invariants that make later `@safe` access valid.

For each typed representation it must validate at least:

1. the descriptor block remains alive for the complete lease lifetime;
2. every plane descriptor refers to storage retained by that representation;
3. the sample type interpretation is correct for the backing storage;
4. base addresses satisfy the alignment requirements of `T`;
5. row/sample stride conversion is representable;
6. byte strides imported from external APIs are compatible with `sizeof(T)`;
7. region coordinates and extents are representable;
8. region containment arithmetic cannot overflow;
9. pointer-offset arithmetic cannot overflow;
10. every reachable sample lies inside an appropriate retained resource;
11. negative strides, when accepted, remain inside the retained resource;
12. `width * height` is representable before 1D linear adaptation;
13. writable views are created only for writable retained storage;
14. stable descriptor metadata is not modified after publication;
15. any declared planar/interleaved layout metadata agrees with the
    descriptors.

ROI construction may rely on these established parent-view invariants.

It must still perform containment checks using subtraction-based arithmetic
rather than unchecked `x + width` style expressions.

#### Resource-layer units

R0.3 selects different units at different layers:

```text
RasterView / PlaneDescriptor
    element coordinates
    element strides

Backing/resource representation
    byte addresses
    byte lengths
```

This keeps typed pixel traversal simple and matches the internal Mir mapping.

Conversion from byte-oriented external formats is paid once during validated
construction rather than repeatedly inside hot kernels.

#### Storage topology versus execution layout

These are separate concepts.

Storage topology answers:

```text
How are logical bands physically related?
```

Examples:

```text
planar
pixel-interleaved
custom/composite
```

Execution layout answers:

```text
How may this particular plane/region be traversed efficiently?
```

The tested execution classes are:

```text
arbitrary sample stride
    -> Universal 2D

unit X stride
    -> Canonical 2D

unit X stride + rowStride == region width
    -> Contiguous 2D

fully contiguous + semantically linearizable operation
    -> Contiguous 1D
```

A planar plane may be Canonical or Contiguous.

An interleaved logical band may be Universal.

A narrow ROI cut from a contiguous source may become Canonical rather than
Contiguous.

Therefore the two classifications must never be collapsed into one enum.

#### Multi-band execution

The experiments also demonstrated that representing RGB as three logical
planes must not force execution as three independent physical streams.

For pixel-interleaved storage the execution planner should classify the
shared physical layout and select a physical-stream kernel where appropriate.

The preferred execution relationship is:

```text
logical multi-plane view
        |
        v
layout/topology classifier
        |
        +-- planar contiguous
        |       -> independent linear band streams
        |
        +-- pixel-interleaved RGB/RGBA
        |       -> shared physical stream kernel
        |
        +-- arbitrary strided
                -> generic logical-plane kernel
```

Logical representation and physical kernel schedule are therefore separate.

#### Internal Mir boundary

Mir remains internal.

The public/core semantic model is:

```text
RasterView
PlaneDescriptor
Region2D
RasterLease
```

not:

```text
mir.ndslice.Slice
```

The adapter boundary is:

```text
validated RasterView
        |
        v
small internal adapter
        |
        +-- Universal 2D
        +-- Canonical 2D
        +-- Contiguous 2D
        +-- Contiguous 1D
        |
        v
kernel
```

The adapter is O(1) and allocation-free.

The lifetime experiments demonstrated that adapted Mir slices remain bound to
their originating view/lease.

The code-generation experiment demonstrated that the 1D Contiguous Mir path
produced effectively the same AVX2 hot loop as the raw-pointer baseline on
LDC 1.41 / LLVM 19.1.7.

Mir is therefore accepted as an internal implementation substrate, not as a
public API dependency.

#### Provisional core relationship

The R0.3 target architecture is:

```text
                         retained representation
                                  |
             +--------------------+--------------------+
             |                    |                    |
             v                    v                    v
     backing resources     stable descriptors    storage metadata
             |                    |                    |
             +--------------------+--------------------+
                                  |
                          retained lifetime
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             RasterLease!T             MutableRasterLease!T
                    |                           |
                    v                           v
             RasterView!T              MutableRasterView!T
                    ^                           |
                    |                           |
                    +------- read downgrade ----+
                                  |
                                  v
                          Region transformations
                                  |
                                  v
                         execution classifier
                                  |
               +------------------+------------------+
               |                  |                  |
               v                  v                  v
           Universal         Canonical          Contiguous
                                                  |
                                                  +-- 2D
                                                  |
                                                  +-- 1D when linearizable
```

#### What R0.3 deliberately does not decide

The following remain outside the R0.3 core-type decision:

- final public naming;
- exact public constructor/factory naming;
- concrete reference-count implementation;
- cache ownership policy;
- task scheduling;
- thread synchronization;
- exclusive writable borrowing;
- GPU representation;
- SIMD/FMA policy;
- concrete RGB/RGBA convenience wrappers;
- dynamic runtime sample-format dispatch;
- file-format-specific metadata;
- georeferencing metadata.

These can be layered on the selected core semantics.

#### R0.3 conclusion

R0.3 supports a general non-owning multi-plane raster view as the semantic
core.

The selected design is characterized by:

```text
stable borrowed plane descriptors
arbitrary-N-band support
explicit region geometry
allocation-free ROI
separate retained lifetime
separate read/write capability
explicit storage topology outside the hot view
layout classification before execution
Mir as an internal adapter
generic plus specialized execution paths
```

The experiments do not support replacing this model with:

- one universal fixed tile type;
- an RGB-specific core representation;
- a Mir type as the public raster API;
- ownership embedded directly inside every view;
- or one generic runtime-stride kernel for all layouts.

R0.3 is therefore complete.

The next research/implementation phase should translate this provisional
semantic model into the first production core implementation and validate it
against real source/backing adapters.
