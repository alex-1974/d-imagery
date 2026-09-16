# R0.3 Raster View Experiment

This experiment evaluates concrete representations for the d-imagery
kernel-facing raster view.

Candidates will include:

- affine single-base representation;
- per-band `PlaneView` descriptors;
- borrowed descriptor sequences;
- retained descriptor blocks;
- an inline/hybrid representation only if measurements justify it.

The experiment must test both representation capability and generated code.

No candidate becomes part of the public library API merely by appearing in
this experiment.

## Experiment 1 — affine RGB versus per-band descriptors

The first experiment compares:

- candidate A: one affine RGB base with row, pixel and channel strides;
- candidate D-like: stable per-band `PlaneDescriptor` metadata plus region
  geometry.

The per-band representation intentionally uses the same kernel for both:

- interleaved RGB represented as three stride-3 scalar streams;
- three independently allocated planar RGB bands represented as stride-1
  streams.

The first questions are:

1. can both models represent ROI without allocation;
2. what metadata size do they require;
3. does the generic per-band form preserve LLVM optimisation quality for
   interleaved RGB;
4. does it retain the expected efficient planar path.

Runtime benchmarking follows only after generated-code inspection.

## Experiment 2 — layout-specialized execution

The semantic view representations were kept unchanged while the kernel was
given compile-time knowledge of common physical layouts.

Three specialized kernels were evaluated:

- affine tightly-interleaved RGB;
- descriptor-based interleaved RGB with logical stride-3 bands;
- descriptor-based planar RGB with unit-stride bands.

All specialized kernels produced results identical to the generic kernels.

LDC/LLVM vectorized all three native specialized kernels.

The generic runtime-stride kernels remained scalar.

This shows that the `PlaneDescriptor` representation itself does not prevent
SIMD. Layout classification and execution specialization are required.

## Benchmark result

The benchmark compares six paths:

```text
dynamic affine / interleaved
dynamic planes / interleaved
static affine / interleaved
static planes / interleaved
dynamic planes / planar
static planes / planar
```

Reference runs use:

```text
4096 x 4096 float RGB
24 samples
3 warmups
2 inner iterations
rotating candidate order
LDC -O3 -release -mcpu=native -boundscheck=off
CPU affinity
```

CPU 5 was selected because its SMT sibling was offline on the reference
i7-9750H system.

Three CPU-5 runs preserved the same ordering.

The strongest result is not one absolute timing number but the separation of
semantic representation from execution:

```text
MultiPlaneRasterView
        |
        +-- classify physical layout
                |
                +-- specialized SIMD path
                |
                +-- generic strided fallback
```

The planar specialized path was fastest in all reference runs.

The naive specialized three-stream interpretation of interleaved RGB was
slightly slower than the specialized single-physical-stream affine kernel.
This is treated as an execution-dispatch issue, not as evidence against the
general band-oriented representation.
## Descriptor lifetime

A retained lifetime experiment validates the intended separation between
ownership and raster views.

`RasterBacking` owns multiple independent resources plus a stable
`PlaneDescriptor[]` block. `RasterLease` retains the backing representation,
while `MultiPlaneRasterView` remains non-owning.

Positive probes validate:

- retention of multiple independent planar allocations;
- descriptor lifetime coupled to the retained representation;
- lease copying;
- exactly-once final resource release;
- allocation-free descriptor reuse across ROI;
- safe ROI and nested-ROI use within the lease lifetime.

Compile-fail probes using DIP1000 validate rejection of:

- direct view return beyond a local lease;
- ROI return beyond a local lease;
- nested ROI return beyond a local lease;
- assignment to a longer-lived local;
- assignment to global state;
- storage in an independently living heap object.

Both DMD and LDC produced the expected results.

ROI methods use `return scope` so lifetime provenance is preserved
transitively through view transformations.

The experiment therefore supports:

```text
retained representation
        |
        +-- N backing resources
        +-- stable PlaneDescriptor[]
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

`SafeRefCounted` is used by this experiment as one possible implementation
mechanism; it is not part of the required public semantic model.

Positive compile-only probes are kept under `positive/`.
Expected compile-fail DIP1000 probes are kept under `negative/`.

## Mir adaptation

Mir is evaluated as an internal execution substrate rather than as the
public raster representation.

The tested adapter maps:

```text
arbitrary strided plane     -> Universal 2D
unit x-stride plane         -> Canonical 2D
fully contiguous plane      -> Contiguous 2D
linearizable contiguous op  -> Contiguous 1D
```

A narrow ROI of a larger contiguous raster is correctly classified as
Canonical rather than Contiguous.

Mir adaptation remains allocation-free and preserves the RasterLease /
DIP1000 lifetime relationship.

LDC/LLVM code-generation experiments showed:

```text
Universal 2D              134 instructions
Canonical 2D               57 instructions
Contiguous 2D              57 instructions
Contiguous 1D              37 instructions
raw pointer 1D baseline    39 instructions
```

Universal generated a runtime unit-stride fast path and AVX2 vector code.

Canonical and Contiguous 2D generated substantially simpler row-wise AVX2
loops.

The explicit one-dimensional Contiguous Mir path generated effectively the
same vector hot loop as the raw-pointer baseline.

This supports Mir as a zero-cost internal abstraction for the contiguous
linear fast path while allowing RasterView to retain general two-dimensional
semantics.


## Core-type synthesis

The final R0.3 synthesis separates four concerns:

```text
physical description
lifetime ownership
pixel access capability
execution representation
```

The provisional physical descriptor is access-neutral:

```d
struct PlaneDescriptor
{
    const(void)* base;
    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;
}
```

Logical geometry is represented separately by `Region2D`.

The selected access-capability model is:

```text
MutableRasterView!T
        |
        | O(1) read-only downgrade
        v
RasterView!T
```

Both view types borrow the same stable descriptor block.

Positive DMD/LDC probes validate writable access, descriptor reuse and
capability-preserving ROI.

Compile-fail probes validate that read-only pixel writes and implicit
read-only-to-writable conversion are rejected.

The lifetime remains provided by the retained representation / lease rather
than by the view itself.

Mir remains an internal execution adapter and is not part of the semantic
core API.
