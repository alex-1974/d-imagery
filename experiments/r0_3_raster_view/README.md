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
