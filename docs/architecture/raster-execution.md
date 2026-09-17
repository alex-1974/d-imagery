# Raster Execution Architecture

Status: E1 architecture contract  
Date: 2026-09-17

## 1. Purpose

The raster execution layer bridges d-imagery's semantic raster representation
to execution-oriented representations used by hot loops.

The architectural direction is:

```text
RasterView
    |
    v
per-plane execution classification
    |
    v
internal execution adapter
    |
    v
scalar / SIMD / later parallel kernels
```

`RasterView` remains the semantic object.

Execution classification and execution adapters are internal implementation
details.

Mir may be used as an internal execution substrate, but Mir types must not
become part of the public d-imagery API.

## 2. Scope of E1

E1 defines:

- the execution-layout taxonomy;
- per-plane classification;
- ROI behaviour;
- negative-stride behaviour;
- empty-view behaviour;
- overflow rules;
- the relationship between 2D layout and 1D linear execution;
- the internal boundary by which RasterView may be classified.

E1 does not introduce:

- Mir as a production dependency;
- Mir Slice types;
- image-processing kernels;
- mutable raster access;
- operation graphs;
- schedulers;
- threading;
- caches;
- providers;
- halo scheduling;
- GPU execution.

Mir adaptation belongs to E2.

## 3. Existing semantic invariants

The execution layer builds on the validated raster core.

For a `PlaneDescriptor`:

```text
base
    = descriptor-space coordinate (0, 0)

rowStrideElements
sampleStrideElements
    = signed strides expressed in elements of T
```

For a `RasterView`:

```text
RasterView.region
    = resident descriptor-space region
```

The region is not a LogicalImage/global coordinate.

For a non-empty view, the existing validated-construction boundary already
proves that all reachable descriptor coordinates and affine offsets are
representable and remain inside retained storage.

The execution layer must not reinterpret or weaken those invariants.

## 4. Storage topology and execution layout are different concepts

Storage topology describes physical organization such as:

```text
planar
pixel-interleaved
padded
negative traversal
custom affine
```

Execution layout describes only the traversal guarantees available for one
logical plane of one concrete RasterView.

A RasterView may contain multiple planes with different execution layouts.

Therefore classification is always per plane.

There is no view-wide assumption that all planes have identical physical
layout.

## 5. 2D execution-layout taxonomy

E1 uses three progressively stronger 2D execution layouts:

```text
Universal
    |
    v
Canonical
    |
    v
Contiguous
```

Conceptually, an internal representation may resemble:

```d
enum PlaneExecutionLayout2D : ubyte
{
    universal,
    canonical,
    contiguous
}
```

The exact internal spelling is not a public API commitment.

### 5.1 Universal

Universal is the fallback representation.

It permits arbitrary validated affine traversal:

```text
arbitrary row stride
arbitrary sample stride
positive or negative strides
```

Every valid non-empty plane can be represented as Universal.

### 5.2 Canonical

Canonical means that traversal in the logical x dimension is forward
unit-stride:

```text
sampleStrideElements == 1
```

The row stride remains explicit and may differ from the view width.

Therefore Canonical includes:

```text
padded rows
narrow ROI from a wider parent raster
positive row stride
negative row stride
```

A negative row stride does not invalidate Canonical classification because
only the innermost x dimension is required to be forward unit-stride.

A negative sample stride is not Canonical:

```text
sampleStrideElements == -1
    -> Universal
```

The classifier must not use:

```text
abs(sampleStrideElements)
```

to establish Canonical layout.

### 5.3 Contiguous

For a non-empty plane, Contiguous is stronger than Canonical.

The logical row-major sample sequence represented by the current RasterView
must have no gap between rows.

For a single-row view:

```text
sampleStrideElements == 1
height == 1
```

is sufficient.

The row stride is irrelevant because no transition to another row occurs.

For a multi-row view:

```text
sampleStrideElements == 1
height > 1
width <= ptrdiff_t.max
rowStrideElements == cast(ptrdiff_t) width
```

must hold.

The explicit `width <= ptrdiff_t.max` check is mandatory.

A direct unchecked cast such as:

```d
cast(ptrdiff_t) width
```

must not be used to classify a multi-row view because `width` itself may be
larger than `ptrdiff_t.max` even though every reachable x coordinate of a
validated region remains representable.

A negative row stride can therefore be Canonical but cannot be Contiguous
for a multi-row view.

## 6. Contiguous 1D is a capability, not a fourth exclusive layout class

The 2D layout hierarchy ends at Contiguous.

One-dimensional linear execution is represented as an additional capability
of the current plane/view.

Conceptually:

```text
Universal
    |
Canonical
    |
Contiguous
    |
    +-- linear contiguous storage available?
```

An internal traits value may eventually resemble:

```d
struct PlaneExecutionTraits
{
    PlaneExecutionLayout2D layout2D;

    bool linearContiguous1D;
    size_t flatElementCount;
}
```

Again, these names are internal and are not yet a public API commitment.

For a non-empty view, `linearContiguous1D` may be true only when:

```text
layout2D == Contiguous
```

and:

```text
width * height
```

is representable as `size_t`.

The multiplication must be checked before it is performed.

For example:

```text
height != 0
width <= size_t.max / height
```

must hold before evaluating the product.

`flatElementCount` is meaningful only when the linear capability is present.

This capability describes storage only.

It does not by itself authorize an operation to execute as a flat 1D loop.

A later operation layer must separately decide whether its semantics are
linearizable.

For example, a point operation may be flattenable while a neighborhood or
row-boundary-sensitive operation may still require 2D semantics.

## 7. Empty views

Empty RasterView regions are valid raster geometry.

An empty region is one for which:

```text
width == 0
or
height == 0
```

No sample is reachable.

E1 therefore treats empty views as a special degenerate case.

The conservative 2D classification is:

```text
layout2D = Universal
```

independent of the descriptor strides.

For an empty view the execution traits are:

```text
layout2D            = Universal
linearContiguous1D  = false
flatElementCount    = 0
```

The zero flat count is deterministic metadata only. It does not assert the
linear-contiguous storage capability.

E2 may still represent an empty plane by an appropriate zero-length execution
adapter as a dedicated empty-view case.

Most importantly:

```text
no adapter may calculate the address of region (x, y)
for an empty RasterView
```

The existing backing validator deliberately does not require empty-region
coordinates to be representable as `ptrdiff_t`, because no sample is reachable.

Therefore E2 must special-case empty views before any expression resembling:

```d
base
    + cast(ptrdiff_t) region.y * rowStride
    + cast(ptrdiff_t) region.x * sampleStride
```

is evaluated.

Empty execution adapters may use an appropriate safe zero-length
representation, but must not manufacture an otherwise unnecessary pointer to
the empty region origin.

## 8. ROI behaviour

Execution classification always applies to the current RasterView.

It must not reuse or cache the classification of a parent view unless the
derived view is independently proven to retain the same guarantees.

Example parent:

```text
width        = 4096
rowStride    = 4096
sampleStride = 1
```

Full view:

```text
Contiguous
```

Narrow ROI:

```text
x            = 100
width        = 512
rowStride    = 4096
sampleStride = 1
```

Result:

```text
Canonical
not Contiguous
```

because rows of the ROI remain separated by the parent row stride.

A row-subset ROI that retains the complete physical row width may remain
Contiguous.

A single-row ROI with unit x-stride is Contiguous regardless of its stored
row stride because no row transition occurs.

## 9. Per-plane classification

Classification is always performed independently for each logical plane.

For example, a RasterView may legally contain:

```text
Plane 0 -> Contiguous
Plane 1 -> Canonical
Plane 2 -> Universal
```

No classifier or execution adapter may assume:

```text
one RasterView == one physical execution layout
```

Interleaved RGB illustrates why.

Three logical descriptors may refer to one physical allocation:

```text
R sampleStride = 3
G sampleStride = 3
B sampleStride = 3
```

Each logical plane is therefore Universal under the generic scalar-plane
classification even though the physical storage as a whole is tightly
interleaved.

Specialized multi-plane execution may later recognize such relationships, but
that is a separate optimization and not part of E1.

## 10. Negative strides

Signed strides are part of the raster-core contract.

The execution layer must preserve them.

For non-empty views:

```text
sampleStride ==  1, rowStride > 0
    -> at least Canonical

sampleStride ==  1, rowStride < 0
    -> Canonical

sampleStride == -1
    -> Universal

arbitrary signed strides
    -> Universal
```

For multi-row Contiguous classification:

```text
rowStride == width
```

is required exactly.

The implementation must never evaluate:

```text
abs(ptrdiff_t.min)
```

or otherwise negate `ptrdiff_t.min`.

The existing validation layer already handles signed stride magnitudes safely;
execution classification should not duplicate unsafe signed-magnitude
arithmetic.

## 11. Overflow rules

E1 classification must not introduce unchecked arithmetic.

In particular:

```text
width * height
```

must be checked before computing a flat length.

For multi-row Contiguous classification, `width` must be proven representable
as `ptrdiff_t` before comparison with `rowStrideElements`.

E1 classification itself does not need to recompute sample-address offsets.

Those address-reachability properties have already been proven by validated
RasterView construction.

E2 may rely on those invariants for non-empty views, but any new arithmetic
introduced by an adapter remains responsible for its own preconditions.

## 12. Internal RasterView boundary

RasterView's descriptor array remains private.

E1 must not make:

```text
planes_
```

public or expose the raw descriptor slice through the public raster API.

The preferred E1 boundary is a narrow package-internal query that returns
classification information rather than a raw descriptor.

Conceptually:

```text
RasterView
    |
    | private PlaneDescriptor[]
    |
    +-- package-internal classification bridge
            |
            v
       PlaneExecutionTraits
```

The returned traits contain execution metadata only.

They contain no storage-owning object and need not contain a pixel pointer.

The actual classifier should be a small pure function over already validated
descriptor metadata and the current Region2D.

This keeps the semantic RasterView encapsulation intact while allowing later
internal execution modules to dispatch efficiently.

## 13. Safety requirements for E1

E1 classification should be implementable as:

```text
@safe
pure
nothrow
@nogc
```

No new `@trusted` or `@system` boundary should be required.

E1 must not:

```text
dereference PlaneDescriptor.base
perform pixel pointer arithmetic
change ownership
extend borrow lifetime
return PlaneDescriptor[] publicly
return mutable pixel capability
```

An invalid plane index must produce a controlled failure result and must not
read outside the descriptor array.

The intended package-internal query contract is:

```text
valid plane index
    -> true
    -> traits contain classification

invalid plane index
    -> false
    -> traits == PlaneExecutionTraits.init
```

No exception or sentinel plane index is required.

## 14. Lifetime model

Execution classification is metadata-only and does not extend storage
lifetime.

The existing lifetime chain remains:

```text
RasterBacking
      ^
      |
RasterLease
      |
      | borrow
      v
RasterView
```

E1 traits are ordinary values and contain no owning storage capability.

E2 execution adapters will borrow pixel storage through RasterView and must
preserve the same lifetime provenance.

Any Mir slice created from RasterView must not outlive the RasterView/lease
borrow from which it was derived.

DIP1000 compile-positive and compile-negative probes must be added in E2 if
the adapter introduces a new borrowed pointer-bearing type.

## 15. Read-only capability

The current RasterView is read-only.

Execution adaptation must not upgrade that capability.

Production Mir adapters must therefore use read-only element access, e.g.
conceptually:

```d
Slice!(const(T)*, 2, Universal)
Slice!(const(T)*, 2, Canonical)
Slice!(const(T)*, 2, Contiguous)
Slice!(const(T)*, 1, Contiguous)
```

and not writable `T*` slices.

Writable execution belongs to the future MutableRasterView capability.

## 16. Mir boundary

Mir is not part of E1.

The root d-imagery package therefore does not need a Mir dependency merely to
implement layout classification.

The R0.3 research environment currently resolves:

```text
mir-algorithm 3.22.4
```

E2 must revalidate its concrete adapter against the production dependency
selected at that time.

Mir types must remain below the internal execution boundary.

No Mir type may be re-exported from:

```text
imagery
imagery.raster
```

or another public d-imagery API module.

## 17. Required E1 tests

E1 must mechanically test at least:

```text
arbitrary affine plane
    -> Universal

interleaved scalar band, sampleStride = 3
    -> Universal

negative sample stride
    -> Universal

unit sample stride with padded rows
    -> Canonical

unit sample stride with negative row stride
    -> Canonical

fully contiguous multi-row plane
    -> Contiguous

narrow ROI of contiguous parent
    -> Canonical

full-row subset ROI
    -> Contiguous when current width matches row stride

single-row unit-stride ROI
    -> Contiguous regardless of row stride

mixed planes in one RasterView
    -> independently classified

flat element-count overflow
    -> no linear 1D capability

width greater than ptrdiff_t.max
    -> no erroneous multi-row Contiguous classification

ptrdiff_t.min stride values
    -> no overflow and no abs/negation trap

0 x 0 view
    -> empty semantics

0 x N view
    -> empty semantics

N x 0 view
    -> empty semantics

invalid plane index
    -> controlled failure
```

Both DMD and LDC must pass the same classification tests.

## 18. E1 implementation shape

The expected minimal production change is approximately:

```text
docs/architecture/raster-execution.md

source/imagery/raster/internal/execution_layout.d
    internal layout enum
    internal traits value
    pure descriptor/region classifier
    checked flat-count logic
    unit tests

source/imagery/raster/view.d
    narrow package-internal bridge from private descriptor
    to execution traits
```

The following should remain unchanged in E1 unless implementation evidence
forces a correction:

```text
dub.sdl
source/imagery/raster/package.d
RasterLease
RasterBacking
public RasterView API
construction ownership model
validation ownership/reachability model
```

## 19. E1 / E2 boundary

E1 ends at:

```text
RasterView
    |
    v
per-plane PlaneExecutionTraits
```

E2 begins at:

```text
PlaneExecutionTraits
    +
RasterView borrow
    |
    v
internal Mir Slice
```

E2 is responsible for:

```text
production Mir dependency
const(T)* Mir types
region-base pointer formation
empty-view adapter behaviour
minimal @trusted boundary if required
DIP1000 adapter probes
adapter correctness tests
```

No image operation is required to complete E1 or E2.

## 20. Performance principle

Classification correctness comes before fast-path optimization.

After production adapters exist, the R0.3 code-generation probes should be
repeated against those adapters.

The relevant evidence is not only benchmark time but also:

```text
optimizer visibility
vectorization
runtime stride versioning
generated hot-loop structure
unnecessary abstraction overhead
```

The desired long-term execution architecture remains:

```text
public d-imagery semantics
        |
        v
internal per-plane classification
        |
        v
internal execution representation
        |
        v
scalar / SIMD / later parallel execution
```

## E2 implementation validation baseline

The initial production Mir execution adapter was validated against:

- `mir-algorithm 3.22.4`;
- `mir-core 1.7.4`;
- DMD with `-preview=dip1000`;
- LDC with `-preview=dip1000`.

The root package declares `mir-algorithm ~>3.22.4`; Mir remains an internal
execution substrate and is not part of the public semantic raster API.

The validated adapter properties include:

- `Slice!(const(T)*, 2, Universal)`;
- `Slice!(const(T)*, 2, Canonical)`;
- `Slice!(const(T)*, 2, Contiguous)`;
- `Slice!(const(T)*, 1, Contiguous)`;
- negative outer Canonical strides;
- empty Universal slices using a null iterator;
- read-only element access;
- DIP1000 rejection of a Mir slice escaping a local `RasterLease`.

`dub.selections.json` remains a local DUB resolution artifact for this library
and is not part of the repository contract.

## E3 scalar reference reduction baseline

E3 introduces internal scalar reference kernels on top of the E2 Mir execution
representations.

The initial reference reduction is scalar summation with an explicit caller
selected accumulator type.

The execution layer deliberately does not choose numeric widening or
floating-point precision policy. For example, callers may select `ulong` for
small unsigned integer samples or `double` for floating-point samples.

Arithmetic otherwise follows the normal D semantics of the selected
accumulator type.

Reduction identity values are operation semantics, not D default
initializers. Scalar summation therefore starts from explicit numeric zero
rather than `Accumulator.init`; floating-point `.init` is NaN in D.

The E3 baseline provides separate entry points for:

- Universal 2D;
- Canonical 2D;
- Contiguous 2D;
- flat Contiguous 1D.

At this stage there is deliberately no automatic RasterView dispatch, public
operation abstraction, SIMD specialization, parallel execution, or scheduler.

The four execution paths must agree for equivalent logical samples. The scalar
implementations therefore serve as the correctness reference for later fast
paths and code-generation work.

This first E3 baseline is intentionally read-only and reduction-oriented.
A genuine pointwise `pixel -> pixel` kernel is deferred until the execution
architecture defines a mutable destination representation rather than
implicitly weakening the read-only `RasterView` contract.

## E3b writable target baseline

Writable output is represented independently from read-only `RasterView`.

The initial internal target contract is a non-owning single-plane
`RasterTargetPlane!T` backed by mutable caller storage. Its first construction
capability is deliberately limited to contiguous storage.

The separation is semantic:

- `RasterView!T` represents read-only input;
- `RasterTargetPlane!T` represents writable output;
- Mir remains an internal execution representation;
- copying a target may create writable aliases;
- the target contract does not promise uniqueness or source/target
  non-overlap.

A contiguous target borrows exactly `width * height` elements from the supplied
storage after checked size multiplication. Empty targets preserve their logical
dimensions and expose no reachable execution element.

The writable Mir execution adapters use `Slice!(T*, 2, Contiguous)` and
`Slice!(T*, 1, Contiguous)`.

DIP1000 is required to preserve the complete borrow chain:

    caller mutable storage
        -> RasterTargetPlane
        -> writable Mir Slice

Returning either the target or its Mir execution view is permitted only when
the originating caller-owned storage outlives the return value. Targets backed
by local storage must not escape through a return value or global assignment.

No additional `@trusted` boundary is required for the initial writable target
contract.

General padded, strided, negative-stride, ROI, and multi-plane target semantics
are deliberately not claimed by this baseline. They can be added as separately
validated construction capabilities without weakening the read-only
`RasterView` contract.

## E3c scalar pointwise copy baseline

E3c introduces the first scalar source-to-target execution kernel.

The initial operation is exact same-sample-type copy:

    read-only source -> writable contiguous target

Supported source execution layouts are:

- Universal 2D;
- Canonical 2D;
- Contiguous 2D;
- flat Contiguous 1D.

The target remains the contiguous writable E3b baseline.

Numeric conversion is deliberately excluded from this first pointwise
contract. Defining conversion would require explicit choices for narrowing,
rounding, saturation, and floating-point/integer behavior rather than merely
testing execution topology.

Two-dimensional and flat kernels validate shape equality before the first
target write. A shape mismatch therefore leaves the target unchanged.

Source/target overlap is not guaranteed by the E3c baseline. The execution
layer currently promises correct copy semantics only when the caller's alias
policy makes the traversal valid. Exact overlap, partial overlap, and later
parallel/SIMD alias requirements remain separate operation/execution-policy
concerns.

The scalar copy kernels are the pointwise correctness reference for later fast
paths and code-generation inspection.
