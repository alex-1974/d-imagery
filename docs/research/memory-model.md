# R0.2 Memory Model Research

Status: **ACTIVE**

This document records the memory-view experiments for `d-imagery`.

The first part of R0.2 investigates the representation and traversal of
resident raster data. Later R0.2 work will investigate channel layout,
external buffers, ownership/lifetime, and related memory-model questions.

## 1. Research questions

The initial view experiment asks:

1. Can a small strided raster view represent contiguous images and zero-copy
   rectangular ROIs efficiently?
2. Does a custom D view provide a measurable advantage over `mir.ndslice`?
3. Can LDC/LLVM optimize through the view abstraction?
4. Does the abstraction inhibit automatic SIMD vectorization?
5. Can contiguous storage use a specialized fast path without abandoning the
   generic strided representation?
6. Does native CPU targeting benefit the competing representations equally?

The experiment intentionally does not define the public `d-imagery` API.

## 2. Architectural context

`d-imagery` must distinguish several concepts that are often incorrectly
collapsed into a single "tile" abstraction:

```text
ProviderTile != CacheBlock != Region != ProcessingTask
```

The resident raster representation therefore needs to support arbitrary
rectangular regions and strides rather than assuming that processing always
operates on fixed tiles.

Current conceptual layering:

```text
LogicalImage
    |
    +-- metadata / full extent
    |
    v
Region request
    |
    v
Operation dependency
    |
    v
Required input region
    |
    v
Source / cache
    |
    v
resident RasterView
    |
    v
execution policy
  /    |    \
scalar SIMD parallel
```

The public API must not depend directly on Mir types even if Mir is used as an
internal implementation substrate.

## 3. Competing representations

The experiment compares:

### A. Plain contiguous D slice

A normal one-dimensional D array/slice.

Purpose:

- lower-bound reference;
- contiguous traversal;
- compiler-friendly baseline.

### B. Custom strided 2D view

Prototype metadata:

```d
T* ptr;
size_t height;
size_t width;
size_t rowStride;
```

The stride is measured in elements.

The view supports zero-copy rectangular subviews.

### C. `mir.ndslice` contiguous view

A two-dimensional Mir slice over contiguous storage.

### D. `mir.ndslice` strided ROI

A zero-copy rectangular subview whose logical row width is smaller than the
source row stride.

### E. `mir.ndslice.flattened`

A one-dimensional zero-copy view used as the contiguous fast path.

## 4. Toolchain

Initial test system:

- DMD 2.111.0
- LDC 1.41.0
- LLVM 19.1.7
- `mir-algorithm` 3.22.4
- `mir-core` 1.7.4
- Intel Core i7-9750H
- 6 physical cores / 12 hardware threads
- 12 MiB shared L3 cache

DMD is treated primarily as the development/correctness compiler.

LDC is the primary compiler for performance investigation.

## 5. Benchmark geometry

Current experiment:

```text
full image: 4096 x 4096
ROI:        2048 x 2048
ROI origin: 1024,1024
```

For `ubyte`:

```text
full image = 16 MiB
ROI        =  4 MiB logical data
```

The ROI is genuinely strided:

```text
logical row width = 2048 elements
physical row step = 4096 elements
```

It is therefore not equivalent to a contiguous 2048 x 2048 allocation.

## 6. Kernels

### 6.1 Read reduction

```text
sum(pixel values)
```

This primarily tests traversal and view overhead.

### 6.2 Float point transform

```text
dst = src * gain + bias
```

This was chosen as a deliberately auto-vectorizable read/write kernel.

It tests whether the view abstraction prevents LLVM from generating SIMD code.

## 7. Benchmark methodology

The initial `best-of-7` harness proved too sensitive to:

- CPU turbo state;
- thermal state;
- cache state;
- scheduler effects;
- fixed candidate ordering;
- short individual measurements.

The stabilized harness uses:

```text
3 warm-up rounds
24 measured samples
multiple kernel iterations per sample
CPU affinity via taskset
median
p10
p90
rotating candidate order
```

Twenty-four samples were selected because the current benchmark groups contain
2, 3, or 4 candidates, so every candidate occupies every execution position
equally often.

Example rotation for four candidates:

```text
sample 0: A B C D
sample 1: B C D A
sample 2: C D A B
sample 3: D A B C
```

This change was essential. Earlier large apparent differences between the
representations disappeared when ordering was balanced.

## 8. View metadata size

Observed on x86-64:

```text
custom StridedView2D: 32 bytes
ndslice contiguous:   24 bytes
ndslice ROI:          32 bytes
```

These sizes are not considered performance-critical for pixel-heavy kernels,
but they may later matter for engines managing very large numbers of small
queued regions.

## 9. Portable-codegen findings

### 9.1 `ubyte` reduction

Without native CPU targeting, the original reduction was scalar but unrolled.

The custom view and `ndslice` both optimized down to straightforward inner
loops without per-pixel abstraction calls.

### 9.2 Float transform

LDC vectorized:

```text
plain contiguous
custom strided
ndslice contiguous
ndslice ROI
ndslice flattened
```

The portable build used 128-bit XMM SIMD.

Representative vector body:

```asm
movups
movups
mulps
mulps
addps
addps
movups
movups
```

Eight `float` values are processed per unrolled vector loop iteration.

The custom `opIndex` abstraction did not result in a function call in the hot
pixel loop.

## 10. `ndslice.flattened`

A contiguous `ndslice` can be flattened without copying.

The generated assembly for the flattened view is effectively the same as the
plain D-slice implementation:

```text
alias check
vector loop
scalar remainder
return
```

This establishes a useful specialization model:

```text
internal raster view
        |
        v
     ndslice
      /    \
     /      \
contiguous   strided / ROI
    |             |
flattened       generic 2D
fast path          path
```

The flattened path is an optimization of traversal, not a different ownership
model.

## 11. Stabilized portable benchmark result

After rotating candidate order, no stable meaningful performance advantage
remained for the custom view.

### `ubyte`, full image

All three representations were approximately:

```text
3.8 GPixel/s
```

Differences were generally around or below one percent.

### `ubyte`, strided ROI

Custom and `ndslice` were effectively tied.

### Float transform, full image

Typical range:

```text
~1.78 - 1.85 GPixel/s
```

Plain, custom, `ndslice` 2D, and `ndslice.flattened` exchanged small leads
between runs.

There was no stable ranking.

### Float transform, ROI

Custom and `ndslice` were likewise effectively tied.

## 12. Native CPU targeting

The same benchmark was rebuilt with:

```text
-mcpu=native
```

on the Intel Core i7-9750H.

LLVM then generated AVX2/YMM code.

### 12.1 `ubyte` reduction

Representative instructions:

```asm
vpmovzxbq
vpaddq
vextracti128
```

Throughput increased from roughly:

```text
~3.8 GPixel/s
```

to approximately:

```text
~8.0 GPixel/s
```

depending on run and thermal state.

The improvement applied equally to:

```text
plain
custom strided
ndslice
```

### 12.2 Float transform

Representative native vector body:

```asm
vbroadcastss
vmulps
vaddps
vmovups
```

with 256-bit YMM registers.

Again, no stable performance difference emerged between:

```text
plain contiguous
custom strided
ndslice contiguous
ndslice flattened
```

The full-image transform remained near roughly 1.8-1.9 GPixel/s.

FMA was not emitted in this experiment.

Floating-point contraction and explicit FMA policy belong to later CPU/SIMD
research rather than this memory-view decision.

## 13. Findings

### Confirmed

1. Zero-copy rectangular ROI views are practical.
2. Arbitrary row strides do not inherently prevent efficient traversal.
3. The custom `opIndex` abstraction is optimized away in tested kernels.
4. `mir.ndslice` does not introduce observable per-pixel abstraction overhead.
5. LDC auto-vectorizes through both the custom view and `mir.ndslice`.
6. `ndslice` ROI remains SIMD-compatible.
7. `ndslice.flattened` produces a contiguous fast path essentially equivalent
   to a normal D slice.
8. `-mcpu=native` enables AVX2 for all competing representations rather than
   favoring one representation.
9. After fixing benchmark ordering, no stable performance advantage for the
   custom view remains.

### Rejected as current justification

The hypothesis:

> A custom raster view is required because `mir.ndslice` is too expensive in
> hot pixel loops.

is not supported by the measurements.

## 14. Current architectural direction

Use Mir as the leading candidate for the **internal resident view substrate**:

```text
public d-imagery semantics
        |
        v
internal RasterView abstraction
        |
        v
mir.ndslice implementation
```

Important:

- public APIs should not expose Mir-specific types;
- logical image extent remains separate from resident storage;
- contiguous storage should be eligible for a flattened fast path;
- generic strided 2D traversal remains necessary for ROIs and externally
  strided storage;
- operation semantics must remain separate from execution policy.

This is a provisional architecture decision for R0.2, not a permanent public
API commitment.

## 15. Remaining R0.2 questions

### 15.1 Channel layout

Compare:

```text
interleaved RGB:
RGBRGBRGB...

planar RGB:
RRRR...
GGGG...
BBBB...
```

Representative kernels:

- RGB -> grayscale;
- per-channel gain/bias;
- channel extraction;
- simple multi-channel transforms.

### 15.2 External storage

Investigate views over:

- externally allocated buffers;
- decoder-owned memory;
- memory-mapped storage;
- possibly aligned allocations.

### 15.3 Ownership and lifetime

Separate:

```text
storage ownership
view lifetime
logical image identity
resident region lifetime
cache lifetime
```

Views should remain cheap non-owning descriptors.

### 15.4 Stride semantics

Current prototype expresses row stride in elements.

Later design must determine whether the engine boundary requires:

- element stride;
- byte stride;
- both;
- channel stride / plane stride.

## 16. R0.2 status

```text
R0.2 Memory Model Research                     ACTIVE

  View representation                          DONE
  Zero-copy ROI / stride traversal              DONE
  LDC abstraction-elision check                 DONE
  Portable SIMD check                           DONE
  Native AVX2 check                             DONE
  Benchmark methodology                         DONE

  Interleaved vs planar layout                  DONE
  External buffers                              NEXT
  Ownership / lifetime                          OPEN
  Final memory-model synthesis                  OPEN
```

## Channel-layout findings

R0.2 compared float RGB storage in two layouts:

- interleaved / AoS-like: `RGB RGB RGB ...`
- planar / SoA-like: `RRR... GGG... BBB...`

The purpose was not to select a universal storage format, but to determine
whether channel layout materially affects CPU execution and therefore needs to
be represented explicitly by the engine.

### RGB to grayscale

The grayscale kernel reads all three channels and produces one output channel.

Portable measurements consistently favored planar storage. Native AVX2
measurements reduced the variance and showed a stable planar throughput
advantage of approximately 26%.

Assembly explains the difference.

For planar input, each channel is already a linear SIMD stream. The hot loop
loads R, G and B vectors directly, performs the weighted arithmetic, and
stores grayscale vectors.

For interleaved input, LLVM also vectorizes the operation, but first has to
reconstruct separate R, G and B vectors from `RGBRGB...`. On AVX2 this requires
multiple `vblendps` and `vpermps` operations for each group of pixels.

Conclusion:

- both layouts are SIMD-compatible;
- planar avoids repeated in-register deinterleaving for channel-combining
  operations.

### Single-channel extraction

Materialized green-channel extraction showed a much larger difference.

The planar implementation is a linear copy from the G plane. Native code is a
straight YMM load/store loop.

The interleaved implementation has a stride of three floats between successive
G samples. Native LLVM used gather operations plus address-vector arithmetic.

Measured planar throughput was approximately twice interleaved throughput.

This benchmark is deliberately conservative for planar storage: a real engine
may often expose an existing plane as a zero-copy view instead of materializing
it at all.

Conclusion:

- band-selective access is a strong planar use case;
- channel layout must be visible to planning code.

### Channel-specific gain/bias

A per-channel point operation applied independent gain and bias values to R, G
and B while reading and writing all three channels.

This removes the reduced-input-bandwidth advantage of channel extraction:
both layouts touch the complete RGB image.

Planar nevertheless remained substantially faster.

Native assembly showed why:

- planar uses a regular AVX2 loop over eight samples from each channel;
- interleaved does not vectorize efficiently across multiple RGB pixels when
  different coefficients repeat with period three.

Native measurements showed roughly 47-54% higher planar throughput.

Conclusion:

- the planar advantage is not limited to reduced memory traffic;
- channel-specific arithmetic can expose a substantial SIMD-layout effect.

### Channel-uniform gain/bias

A counterexample applied the same gain and bias to every RGB component.

In this case an interleaved buffer can be treated simply as one contiguous
float stream.

Native LLVM generated an efficient AVX2 loop over 32 consecutive components
for the interleaved representation. The planar implementation also generated
a regular AVX2 loop.

Native performance was effectively equal; the measured planar difference was
only about 1%, with overlapping timing distributions.

Conclusion:

- interleaved storage is not intrinsically slower;
- layout penalties arise from the relationship between layout and operation;
- channel-uniform operations should normally process the existing layout
  directly.

### Layout conversion

Both explicit conversions were measured:

- interleaved to planar;
- planar to interleaved.

For a 4096 x 4096 float RGB image, native median timings averaged approximately:

| Conversion | Mean median |
|---|---:|
| interleaved -> planar | 31.82 ms |
| planar -> interleaved | 32.60 ms |
| roundtrip | 64.42 ms |

AVX2 vectorizes both directions, but neither conversion becomes a simple
streaming copy. Deinterleaving and interleaving require permutations, blends,
and shuffles.

There was no stable evidence that either conversion direction is inherently
cheaper.

Using the measured native operation differences gives approximate break-even
orders of magnitude:

| Operation | I->P only | I->P->I |
|---|---:|---:|
| RGB -> grayscale | ~8 operations | ~16 operations |
| single-channel extraction | ~3 operations | ~6 operations |
| channel-specific gain/bias | ~4 operations | ~7 operations |
| channel-uniform gain/bias | ~134 operations | ~270 operations |

These numbers are experimental observations for this machine and benchmark,
not production scheduling thresholds.

### Channel-layout conclusion

R0.2 rejects both simplistic alternatives:

1. interleaved should not be the mandatory internal processing layout;
2. planar should not be the mandatory universal storage layout.

Instead, channel layout should be explicit raster metadata.

Both planar and interleaved representations are first-class layouts.

The preferred processing strategy depends on the operation:

- channel-uniform processing can efficiently retain the source layout;
- band-selective, channel-combining, and channel-specific pipelines often
  favor planar storage;
- conversion should be considered only when the expected downstream savings
  exceed its cost.

A future execution planner may therefore choose a layout transformation for a
sufficiently long operation chain, but individual image operations should not
encode a universal layout assumption.

Provisional model:

```text
RasterView
    |
    +-- geometry / extent / strides
    |
    +-- channel layout
            |
            +-- interleaved
            |
            +-- planar
```

Channel layout is a property of the resident raster representation, not of the
logical image operation itself.

