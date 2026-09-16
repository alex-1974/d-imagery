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
R0.2 Memory Model Research                     DONE

  View representation                          DONE
  Zero-copy ROI / stride traversal              DONE
  LDC abstraction-elision check                 DONE
  Portable SIMD check                           DONE
  Native AVX2 check                             DONE
  Benchmark methodology                         DONE

  Interleaved vs planar layout                  DONE
  External buffers                              DONE
  Ownership / lifetime                          DONE
  Final memory-model synthesis                  DONE
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

## External buffers and ownership

R0.2 also investigated whether raster views need to participate directly in
memory ownership.

The experiments covered:

- GC-independent external memory;
- `malloc` / `free`;
- anonymous `mmap` storage;
- decoder-style buffers with opaque release context and custom deleter;
- shared ownership through `SafeRefCounted`;
- completely borrowed foreign buffers with no retain/release contract;
- DIP1000 escape analysis for views containing aliases into backing storage.

### Non-owning RasterView

The experiments support keeping `RasterView` fully non-owning.

A view describes raster access:

- pointer or typed memory alias;
- extent;
- strides;
- channel layout;
- mutability.

It does not:

- own the allocation;
- know the allocation mechanism;
- contain a release callback;
- identify the cache or decoder;
- increment reference counts during kernel traversal.

This keeps the kernel-facing type small and independent of storage policy.

### Retainable storage

Memory that d-imagery can retain or release uses a separate storage control
object.

The experimental minimum was:

```text
RasterStorage
    base
    byteLength
    releaseContext
    releaseFn
```

The same representation successfully managed:

- malloc-backed memory;
- mmap-backed memory;
- decoder-style external memory using an opaque context and custom release
  function.

`SafeRefCounted` was used experimentally to retain the storage.

Multiple lease copies shared the same allocation and the configured release
operation ran exactly once when the final owner disappeared.

The resulting model is:

```text
RasterStorage
      ^
      | SafeRefCounted
      |
RasterLease
      |
      | return/scope lifetime
      v
RasterView
```

### Lease-bound views

A `RasterLease` retains backing storage.

Its `view()` operation produces a non-owning view whose lifetime is bound to
the lease through DIP1000 `return` semantics.

Positive tests confirmed that:

- views are usable locally in `@safe` code;
- leases can be copied;
- a copied lease keeps storage alive after another lease dies.

Negative tests confirmed that both DMD and LDC reject:

- returning the view after its lease would die;
- assigning the view to a local variable with a longer lifetime.

A small audited `@trusted` boundary is likely necessary where a view is
materialized from retained external storage. The trust invariant is that the
enclosing lease retains the storage for at least the lifetime of the returned
view.

This trust boundary should not extend into normal raster kernels.

### Pure borrowed foreign memory

A different regime is required when an external pointer has no retain or
release contract.

Such memory must not be disguised as owned storage.

The tested model is a scope-limited callback:

```text
foreign memory
      |
      v
withBorrowedRaster(...)
      |
      v
scope RasterView
```

The callback may synchronously read or mutate the foreign memory while the
caller guarantees its validity.

Both DMD and LDC rejected attempts to retain the borrowed view in:

- a longer-lived local variable;
- a module-global variable;
- an object stored on the heap.

Therefore pure borrowed memory can remain available without introducing
artificial ownership.

### Ownership conclusion

R0.2 distinguishes two lifetime regimes.

Retainable memory:

```text
external allocation
      |
      v
RasterStorage
      |
      v
RasterLease
      |
      v
RasterView
```

Pure borrowed memory:

```text
foreign pointer
      |
      v
scope callback
      |
      v
RasterView
```

A foreign pointer should become a `RasterLease` only when d-imagery has a
reliable retain/release or ownership contract.

Otherwise it remains a synchronous borrow.

This separation allows `RasterView` itself to remain fully non-owning.

### Safety assumption

The lifetime experiments were verified with:

- DMD 2.111.0;
- LDC 1.41.0;
- `-preview=dip1000`.

The DIP1000 escape checks are therefore part of the assumptions behind the
current R0.2 memory model and should be reflected in future build and API
design decisions.

## Final memory-model synthesis

R0.2 converges on a memory model based on strict separation between logical
image semantics, resident storage, lifetime management, raster views and
execution policy.

The purpose of this synthesis is to define the architectural constraints for
the next implementation phase. It does not freeze the final public API.

### Overall model

The resulting conceptual pipeline is:

```text
LogicalImage
    |
    | full extent / metadata
    v
Region request
    |
    | operation dependency
    | halo / context expansion
    v
Required input region
    |
    v
source / cache
    |
    | retainable storage or scoped borrow
    v
RasterLease / borrow scope
    |
    v
RasterView
    |
    +-------------------------------+
    |                               |
    v                               v
generic strided path          contiguous fast path
    |                               |
    v                               v
scalar / SIMD / parallel execution policy
```

The important boundaries are:

```text
ProviderTile != CacheBlock != Region != ProcessingTask
```

None of those concepts should be collapsed into one universal tile object.

### Logical image versus resident memory

A logical image represents the complete image domain and associated metadata.

It does not imply that the complete image is resident in memory.

Processing begins with a requested `Region`. An operation may expand that
region according to its dependency requirements, for example to obtain a halo
for convolution, resampling or neighborhood operations.

Only the required input region needs to become resident.

The desired correctness property remains:

```text
F(whole image)[R]
    approximately equals
F(required streamed region with sufficient context)[R]
```

subject to explicitly documented border and numerical semantics.

This is the central mechanism that allows imagery substantially larger than
available RAM.

### Region is the processing primitive

R0.2 does not select a universal fixed processing tile size.

Fixed provider tiles and cache blocks remain useful implementation details,
but the processing abstraction is an arbitrary rectangular region.

A requested region may therefore:

- be smaller than a provider tile;
- span multiple provider tiles;
- overlap cache blocks;
- contain additional halo pixels;
- be subdivided differently by an execution scheduler.

This follows the useful separation seen in demand-driven and streamed image
engines.

### RasterView is non-owning

`RasterView` is the kernel-facing description of resident raster data.

It is deliberately non-owning.

Conceptually it contains only information required to interpret pixels, such
as:

- one or more data pointers or plane descriptors;
- spatial extent;
- row stride;
- pixel/channel stride or equivalent layout information;
- channel layout;
- element type and constness.

It does not:

- own memory;
- free memory;
- retain decoder resources;
- manage cache entries;
- identify the source provider;
- perform reference counting while pixels are traversed.

This keeps hot-path traversal independent of memory-management policy.

### Single-base storage must not be assumed

The simple lifetime probes used one backing allocation per storage object.

That is sufficient to validate the ownership model but must not become an
architectural restriction.

Real imagery may use:

- one interleaved allocation;
- one allocation containing multiple planar bands;
- multiple separately allocated planes;
- decoder-managed plane arrays;
- mapped file regions;
- externally supplied buffers.

Therefore the final implementation must be capable of describing one or more
resident planes without assuming that every channel can be expressed as an
offset from one common base pointer.

The exact representation remains an implementation/API design decision.

### Channel layout is explicit

R0.2 rejects both universal-layout assumptions:

- interleaved is not mandatory;
- planar is not mandatory.

Both are first-class raster layouts.

Measured behavior showed:

```text
operation                          interleaved       planar

channel-uniform point operation       ideal           ideal
RGB -> grayscale                    deinterleave      linear streams
single-band access                  gather/stride     linear / view
channel-specific point operation    weak SIMD         strong SIMD
```

Native channel-uniform processing reached practical parity.

Planar processing was substantially faster for channel-selective and
channel-specific work.

Therefore channel layout is part of resident raster metadata and must be
visible to planning code.

### Layout conversion is a scheduling decision

Explicit RGB layout conversion cost approximately the same in both directions
on the R0.2 test machine.

Conversion itself remained a substantial operation even under AVX2 because it
requires permutations, blends and shuffles rather than a simple memory copy.

Consequently an individual image operation should not silently convert layout
for its own convenience.

Instead, a future planner may choose to convert once when a sufficiently long
downstream operation chain benefits from the alternative layout.

Conceptually:

```text
source/native layout
        |
        +-- uniform operations --------------------+
        |                                          |
        | preserve layout                          |
        v                                          |
      output                                       |
                                                   |
        +-- band/channel-heavy pipeline            |
        |                                          |
        v                                          |
 optional one-time layout conversion               |
        |                                          |
        v                                          |
 multiple downstream operations ------------------+
```

Conversion thresholds must not be hard-coded from the R0.2 benchmark numbers.
They are hardware-, datatype- and kernel-dependent.

### Generic strided path plus contiguous fast path

R0.2 found no persistent performance reason to replace Mir `ndslice` with a
custom public/internal multidimensional traversal abstraction.

The current preferred direction is:

```text
public d-imagery semantics
        |
        v
internal RasterView
        |
        v
Mir ndslice adaptation
        |
        +-- contiguous -> flattened fast path
        |
        +-- strided / ROI -> generic multidimensional path
```

The public API must not expose Mir types.

Mir is an implementation substrate, not part of the semantic contract.

The optimizer experiments showed that the generic strided representation does
not inherently impose per-pixel abstraction overhead when its metadata is
visible to LDC.

### Storage ownership is separate from views

Retainable backing resources use a separate lifetime mechanism.

The experimental model was:

```text
RasterStorage
      ^
      | retained ownership
      |
RasterLease
      |
      | return/scope lifetime
      v
RasterView
```

`SafeRefCounted` successfully demonstrated one viable implementation strategy,
including deterministic release after the final lease disappears.

However, R0.2 does not require that the final implementation use exactly one
`SafeRefCounted!RasterStorage` object.

A lease may ultimately need to retain:

- one allocation;
- several planar allocations;
- a decoder resource object;
- a cache block;
- another composite resource set.

The architectural requirement is lifetime retention, not a specific control
block representation.

### Retainable external memory

External memory can participate in normal lease semantics when d-imagery has a
reliable retention or release contract.

The R0.2 probes validated:

- `malloc` / `free`;
- anonymous `mmap`;
- custom decoder-style release callbacks with opaque context.

A generalized resource descriptor successfully used:

```text
base
byteLength
releaseContext
releaseFn
```

for those tests.

This demonstrates that raster semantics do not need to depend on a particular
allocator or decoder.

### Pure borrowed memory

Foreign memory without a retain/release contract belongs to a different
lifetime regime.

It must not be presented as owned memory.

The tested model is:

```text
foreign memory
      |
      v
withBorrowedRaster(...)
      |
      v
scope RasterView
```

The view may be used synchronously while the caller guarantees that the
foreign memory remains valid.

DIP1000 correctly rejected attempts to store such a view in:

- a longer-lived local variable;
- a module-global variable;
- a heap object.

This preserves zero-copy interoperability without fabricating ownership.

### Mutability belongs in the type system

Mutable and read-only raster access should be distinguished by the element
type rather than by a runtime writable flag where practical.

Conceptually:

```d
RasterView!float
RasterView!(const float)
```

This allows read-only mappings, decoder buffers and immutable processing inputs
to retain compile-time write protection.

The exact public spelling remains to be designed.

### Stride units

The current preferred internal convention is to express typed raster strides
in elements of `T`, not bytes.

Conceptually:

```text
rowStride
pixelStride
channelStride
```

represent element distances.

Adapters for foreign APIs may accept byte pitches, validate alignment and
divisibility, and convert them at the boundary.

Raw storage remains byte-oriented.

This separates:

```text
storage size       -> bytes
typed view stride  -> elements
```

and reduces repeated byte/element arithmetic inside kernels.

This convention remains subject to validation when the concrete public view
types are designed.

### Safety boundaries

The goal is for normal image processing code to remain `@safe`.

Small audited `@trusted` boundaries are expected where unavoidable, notably:

- converting a validated external pointer and length into a typed raster view;
- materializing a lease-bound view from retained storage;
- interfacing with C decoders, mmap and external allocator APIs.

Those boundaries must establish explicit invariants before returning to
`@safe` code.

The lifetime experiments were validated with:

```text
DMD 2.111.0
LDC 1.41.0
-preview=dip1000
```

Therefore DIP1000 escape analysis is currently part of the memory-model safety
assumptions.

### Required view invariants

Before a typed `RasterView` is considered valid, the implementation must be
able to establish at least:

1. every referenced plane remains alive for the complete view lifetime;
2. every reachable element lies inside its validated backing allocation;
3. stride and offset arithmetic does not overflow;
4. typed pointers satisfy the required alignment for `T`;
5. mutable views refer to memory that is actually writable;
6. channel and plane metadata agree with the accessible memory geometry.

These checks belong at construction or trusted-adapter boundaries, not inside
the pixel hot loop.

### Cache interaction

Cache ownership and raster traversal remain separate concerns.

A cache entry may retain the backing storage required by one or more views,
but a `RasterView` must not itself become a cache object.

The expected model is:

```text
source cache / processed cache
            |
            | owns or retains resident data
            v
        RasterLease
            |
            v
        RasterView
```

Processed-cache identity must account for representation properties that
affect interpretation, including channel layout where relevant.

Source caches should normally preserve useful native representations instead
of converting solely for cache uniformity.

### Execution policy remains orthogonal

Raster semantics do not encode whether an operation executes:

- scalar;
- SIMD;
- multi-threaded;
- eventually on a GPU.

The same logical operation and region dependency should be separable from its
execution schedule.

This follows the useful algorithm/schedule separation observed in Halide and
also avoids coupling semantic APIs to the first CPU implementation.

### Concurrency is not solved by lifetime safety

R0.2 establishes object lifetime and escape safety.

It does not establish thread-safety for simultaneous mutable access.

Multiple leases may retain the same backing memory, and multiple mutable views
could therefore alias the same pixels.

Future concurrency design must separately define rules for:

- read/read sharing;
- read/write conflicts;
- write/write conflicts;
- cache mutation;
- processing-task scheduling.

DIP1000 prevents dangling aliases; it does not replace synchronization or
alias-management policy.

### Final R0.2 architecture

The resulting memory architecture is:

```text
                        LogicalImage
                             |
                             v
                      requested Region
                             |
                     operation dependency
                             |
                      halo / expansion
                             |
                             v
                    required input region
                             |
              +--------------+--------------+
              |                             |
              v                             v
        retained storage              pure borrowed
              |                             |
              v                             v
         RasterLease                scoped callback
              |                             |
              +--------------+--------------+
                             |
                             v
                        RasterView
                             |
                +------------+------------+
                |                         |
                v                         v
             planar                  interleaved
                |                         |
                +------------+------------+
                             |
                  strided generic path
                         or
                  contiguous fast path
                             |
                             v
                     execution policy
                  scalar / SIMD / parallel
```

### R0.2 conclusions

R0.2 establishes the following architectural decisions:

1. the complete logical image does not need to be resident;
2. arbitrary `Region` is the processing abstraction;
3. halo/context comes from operation dependency;
4. provider tiles, cache blocks, regions and processing tasks are distinct;
5. `RasterView` is fully non-owning;
6. ownership/lifetime is managed outside the view;
7. retainable and purely borrowed external memory use different APIs;
8. planar and interleaved layouts are both first-class;
9. layout conversion is a planning/scheduling concern;
10. generic strided traversal is required;
11. contiguous storage receives an explicit fast path;
12. Mir `ndslice` is a suitable internal traversal substrate;
13. Mir types must not leak into the public API;
14. mutability should be expressed through the type system where practical;
15. storage/backend identity must not contaminate raster-kernel semantics;
16. small audited `@trusted` boundaries are acceptable at external-memory
    adapters;
17. normal processing code should remain `@safe`;
18. lifetime safety and concurrency safety are separate problems.

### Deferred beyond R0.2

R0.2 intentionally does not finalize:

- exact public `RasterView` field layout;
- exact multi-plane representation;
- exact `RasterStorage` implementation;
- allocator selection;
- thread-safety and mutable-alias policy;
- cache replacement policy;
- async task and cancellation semantics;
- GPU representation;
- final layout-conversion heuristics;
- public operation API.

Those belong to later implementation and execution-model work.

R0.2 therefore closes with the memory-model architecture sufficiently defined
to begin concrete core type design.

