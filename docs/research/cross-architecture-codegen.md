# R0.3 Cross-Architecture Code Generation Validation

Date: 2026-09-16

This document records cross-architecture compiler evidence for the raster-view
execution model investigated during R0.3.

The validation is intentionally about generated machine code rather than
absolute timing. GitHub-hosted runners are not treated as stable performance
benchmark machines.

## Scope

The probe compares the same gain/bias operation implemented through:

- Mir Universal 2D;
- Mir Canonical 2D;
- Mir Contiguous 2D;
- Mir Contiguous 1D;
- a raw-pointer flat-loop reference.

The most important comparison for the fast path is:

Mir Contiguous 1D versus raw pointer.

The semantic operation is:

    value = value * gain + bias

The functions are deliberately kept separate and non-inlined so their
generated machine code can be inspected independently.

## Reproducibility

Repository commit introducing the architecture probe:

    1b2c9a6 ci: add cross-architecture codegen probes

GitHub Actions workflow:

    .github/workflows/architecture.yml

Probe implementation:

    tools/codegen/r0_3_mir_codegen.sh

GitHub Actions validation run:

    35132482700

Validated targets:

    Linux x86-64 / LDC / x86-64-v3
    Linux AArch64 / LDC

The workflow preserves:

- generated assembly;
- LLVM IR;
- compiler and environment metadata;
- DUB import paths;
- selected assembly excerpts;
- architecture-specific instruction summaries.

## x86-64 result

The x86-64 probe targets x86-64-v3 rather than the arbitrary native CPU of a
hosted runner.

The Mir Contiguous 1D fast path vectorizes using AVX2 YMM registers.

The generated vector loop processes 32 floats per unrolled iteration using
four 256-bit vector operations:

    vmulps
    vmulps
    vmulps
    vmulps

followed by:

    vaddps
    vaddps
    vaddps
    vaddps

and four vector stores.

A scalar remainder loop handles the tail.

The corresponding raw-pointer implementation has the same essential hot-loop
structure.

This reproduces the earlier local R0.3 finding that flattening a fully
contiguous Mir slice can reduce to code generation equivalent in structure to
the raw-pointer baseline.

## AArch64 result

The AArch64 result independently confirms the same architectural conclusion.

The Mir Contiguous 1D vector loop processes eight floats per iteration using
two 128-bit NEON vectors.

Its essential loop is:

    ldp     q3, q4, [...]
    fmul    v3.4s, v3.4s, v0.s[0]
    fmul    v4.4s, v4.4s, v0.s[0]
    fadd    v3.4s, v2.4s, v3.4s
    fadd    v4.4s, v2.4s, v4.4s
    stp     q3, q4, [...]

The raw-pointer reference generates the same essential vector-loop structure.

Both implementations also use equivalent scalar remainder loops.

Therefore the zero-cost fast-path conclusion is not specific to x86-64 or
AVX2.

## Floating-point contraction

Neither architecture used fused multiply-add for this probe.

The observed code uses separate multiplication and addition:

    x86-64: vmulps + vaddps
    AArch64: fmul + fadd

This result must not be interpreted as a limitation of RasterView, Mir, or the
execution-layout model.

Floating-point contraction, FMA use, reproducibility requirements, and related
compiler flags belong to a separate numerical-policy decision.

## Architectural conclusion

The evidence supports the following execution model:

    semantic RasterView
            |
            v
    execution classification
       /       |        \
 Universal  Canonical  Contiguous
                         |
                         v
                  linearizable?
                         |
                         v
                  Contiguous 1D
                         |
                  Mir flat adapter
                         |
                LLVM vectorization
                    /        \
                 AVX2        NEON

For fully contiguous and semantically linearizable operations, the internal
Mir Contiguous 1D representation can produce a hot loop equivalent in
structure to a raw-pointer implementation on both tested ISAs.

This supports the existing design decision:

- keep imagery-d's public raster semantics independent of Mir;
- use Mir internally as an execution substrate;
- classify layout before entering hot loops;
- expose contiguous one-dimensional execution only when the operation is
  semantically linearizable;
- retain Universal and Canonical paths for layouts that cannot use the flat
  fast path.

## What this validation does not prove

This experiment does not establish:

- absolute performance equivalence on every CPU;
- identical behaviour for every operation;
- optimal instruction scheduling for every microarchitecture;
- a final FMA or floating-point contraction policy;
- cache behaviour;
- multithreaded scaling;
- GPU suitability.

Those remain separate optimization and execution-policy questions.

## Status

R0.3 cross-architecture code-generation validation: PASS

Validated:

    x86-64 / AVX2
    AArch64 / NEON

The core RasterView representation does not need an ISA-specific semantic API
to obtain architecture-appropriate SIMD code generation for this fast path.
