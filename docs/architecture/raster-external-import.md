# Raster External Import

## Status

C6 design specification.

This document defines the first public retained-storage import boundary built
above the package-internal raster construction layer.

No raw ResourceEntry representation is part of the public API.

## 1. Goals

The import layer must allow externally allocated raster storage to become a
RasterLease while preserving the existing invariants:

- ownership transfers exactly once;
- every adopted resource is released exactly once;
- release callback state remains valid until release;
- caller metadata is not retained accidentally;
- byte-oriented external layouts are validated before becoming
  element-oriented PlaneDescriptors;
- RasterView remains a cheap non-owning borrow;
- global LogicalImage placement remains outside RasterView;
- raw callback/context construction remains behind an audited boundary.

The first C6 adapter deliberately supports one retained physical resource.

This is sufficient for:

- single-band buffers;
- pixel-interleaved RGB/RGBA;
- several logical planes sharing one allocation;
- decoder outputs backed by one allocation;
- external libraries returning one contiguous or strided buffer.

Multi-resource planar import is a later extension.

The underlying RasterBacking already supports that topology.

## 2. Layering

```text
external allocation
        |
        | explicit adoption
        v
OwnedByteResource
        |
        | move-only retained ownership
        v
PlaneByteLayout[]
        |
        | checked conversion for T
        v
PlaneDescriptor[]
        |
        | audited transition
        v
constructRetainedRaster() @system
        |
        v
RasterLease!T
        |
        | borrow
        v
RasterView!T
```

## 3. OwnedByteResource

The public API should expose an ownership token conceptually equivalent to:

```d
struct OwnedByteResource
{
    @disable this(this);

    // implementation-private ownership state
}
```

The public representation must not expose:

- ResourceEntry;
- ReleaseFn;
- releaseContext;
- arbitrary release callback registration.

The token owns exactly one physical byte range.

Destroying an armed token releases that physical resource exactly once.

Moving/adopting the token transfers that obligation.

An empty/disarmed token owns nothing.

## 4. Initial public adoption mechanism

The first public ownership factory should support malloc-compatible storage.

Conceptually:

```d
OwnedByteResource adoptMallocResource(
    void* base,
    size_t byteLength
)
@system;
```

The function is `@system` because the caller is asserting that:

- base identifies an allocation compatible with free();
- byteLength correctly describes that allocation;
- ownership is being transferred;
- the caller will not free the allocation afterward.

Once successfully represented by OwnedByteResource, ordinary manipulation of
the token does not require callers to handle raw release callbacks.

A null base with non-zero byteLength is invalid.

The exact result/error spelling is not frozen by this document.

## 5. Source-specific adoption

Future source adapters may require release mechanisms other than free():

```text
mmap        -> munmap
decoder     -> decoder-specific release
GDAL/C API  -> library-specific destroy/free
GPU staging -> backend-specific release
```

These adapters may create OwnedByteResource through a package-internal
`@system` factory.

That factory may accept ResourceEntry-style release state internally.

It must not become part of the general public API.

Each source adapter is responsible for proving the lifetime of any opaque
release context it installs.

## 6. External plane layout

External APIs commonly describe strides in bytes.

The public import boundary should therefore use byte-oriented layout metadata,
not PlaneDescriptor directly.

Conceptually:

```d
struct PlaneByteLayout
{
    size_t byteOffset;

    ptrdiff_t rowStrideBytes;

    ptrdiff_t sampleStrideBytes;
}
```

`byteOffset` is relative to the start of the owned physical resource.

It identifies descriptor coordinate `(0, 0)` for that logical plane.

Signed byte strides permit validated negative traversal.

## 7. Why PlaneDescriptor is not the import format

PlaneDescriptor is an internal/core execution-facing representation:

```text
base pointer
row stride in T elements
sample stride in T elements
```

An external API generally starts with:

```text
allocation base
byte offset
row stride in bytes
sample stride in bytes
```

Accepting PlaneDescriptor directly would force callers to perform trusted
pointer arithmetic and byte-to-element conversions themselves.

That is precisely the work the import adapter should centralize.

## 8. Checked conversion

For sample type T, each PlaneByteLayout must be converted before raw retained
construction.

The adapter must prove at least:

1. T satisfies isRasterSampleType!T.

2. byteOffset lies within the physical resource.

3. allocation base plus byteOffset is representable.

4. resulting plane base satisfies T alignment.

5. rowStrideBytes is exactly divisible by T.sizeof.

6. sampleStrideBytes is exactly divisible by T.sizeof.

7. converted row stride fits ptrdiff_t.

8. converted sample stride fits ptrdiff_t.

9. resident Region2D endpoint arithmetic is representable.

10. the complete affine footprint lies within the owned physical resource.

The existing backing validator remains the final physical-footprint check.

The adapter performs representation conversion checks before entering the raw
construction layer.

## 9. Signed byte-stride conversion

Signed strides require care.

The conversion must not use unchecked operations whose behavior fails for
ptrdiff_t.min.

Conceptually:

```text
byte stride
    |
    | exact divisibility by sizeof(T)
    v
signed element stride
    |
    | representable in ptrdiff_t
    v
PlaneDescriptor stride
```

The implementation should use explicit checked helpers rather than relying on
implicit casts.

## 10. Ownership semantics of raster adoption

The raster-import operation is an adopting operation.

Conceptually:

```d
RasterImportResult adoptRaster(
    ref OwnedByteResource resource,
    const PlaneByteLayout[] planes,
    Region2D residentRegion,
    out RasterLease!T lease
);
```

The exact API spelling is intentionally not frozen yet.

The ownership contract is more important than the function name.

When adoption begins:

```text
caller
   |
   | transfers OwnedByteResource
   v
import adapter
```

From that point onward exactly one owner must remain responsible for release.

If layout conversion fails after ownership transfer, the adapter releases the
resource.

If raw retained construction fails, its transactional ownership machinery
releases the resource.

If construction succeeds, RasterBacking becomes the owner.

The caller must not retain a second release obligation.

## 11. Why the token is preferable to a naked pointer API

A direct function such as:

```d
adoptRaster(void* base, size_t bytes, ...)
```

would combine too many responsibilities in one call.

A separate ownership token provides:

- explicit ownership state;
- RAII cleanup before raster construction;
- a place to encode disarmed/moved state;
- no public release callback/context;
- a reusable source-adapter boundary;
- easier future support for multiple physical resources.

## 12. First C6 topology

C6 supports:

```text
one OwnedByteResource
        |
        +--> Plane 0
        +--> Plane 1
        `--> Plane N
```

Example pixel-interleaved RGB ubyte:

```text
resource:
    byteLength = width * height * 3

Plane 0:
    byteOffset        = 0
    rowStrideBytes    = width * 3
    sampleStrideBytes = 3

Plane 1:
    byteOffset        = 1
    rowStrideBytes    = width * 3
    sampleStrideBytes = 3

Plane 2:
    byteOffset        = 2
    rowStrideBytes    = width * 3
    sampleStrideBytes = 3
```

This converts naturally into the already-tested shared-resource
PlaneDescriptor topology.

## 13. Planar storage

A single allocation containing consecutive planar bands is also supported by
the first C6 topology.

Example:

```text
resource
+-------------+
| red plane   |
+-------------+
| green plane |
+-------------+
| blue plane  |
+-------------+
```

Each PlaneByteLayout uses a different byteOffset into the same
OwnedByteResource.

Independent per-plane allocations require the later multi-resource extension.

## 14. Borrowed storage is separate

C6 retained import must not attempt to solve pure borrowed storage.

Borrowed storage has different lifetime semantics.

It should eventually use a scoped API conceptually similar to:

```d
withBorrowedRaster(..., scope delegate(RasterView!T) operation)
```

A borrowed pointer must never be disguised as OwnedByteResource by installing
a no-op release callback.

## 15. Mutability is separate

The first external import remains read-only at the RasterView capability
level.

Physical memory may happen to be writable, but read-only RasterLease /
RasterView construction does not grant mutation capability.

Mutable retained import belongs to the later MutableRasterView phase.

## 16. Global coordinates are separate

PlaneByteLayout and resident Region2D describe resident storage only.

Example:

```text
LogicalImage request:
    Region2D(100000, 200000, 512, 512)

imported resident raster:
    Region2D(0, 0, 512, 512)
```

The global placement belongs to request/cache/task metadata above RasterView.

## 17. Safety boundary

The expected safety layering is:

```text
raw pointer ownership claim
        |
        | @system adoption factory
        v
OwnedByteResource
        |
        | safe ownership token
        v
checked layout adapter
        |
        | small audited @trusted implementation
        v
raw retained construction @system
        |
        v
RasterLease
```

The trusted adapter may call the raw @system constructor only after it has
established the invariants promised by its public API.

## 18. Error model

Import-specific errors should remain distinct from backing-validation errors.

Likely categories include:

```text
empty / invalid ownership token
invalid byte offset
misaligned plane base
row stride not divisible by sample size
sample stride not divisible by sample size
stride conversion overflow
construction failure
```

BackingValidationResult should remain available when the final retained
validator rejects the physical footprint.

The exact enum names are not frozen yet.

## 19. Non-goals of C6

C6 does not yet define:

- multiple independently owned physical resources;
- borrowed raster construction;
- mutable raster construction;
- mmap-specific public APIs;
- GDAL-specific public APIs;
- decoder-specific public APIs;
- GPU resources;
- cache ownership;
- global LogicalImage placement;
- runtime sample-type dispatch.

## 20. Required mechanical tests

Before C6 is considered complete, tests should prove:

1. malloc ownership transfers exactly once.

2. failed import releases the allocation exactly once.

3. successful import retains storage until the final RasterLease disappears.

4. caller layout metadata may disappear immediately after import.

5. interleaved shared-resource RGB maps to correct logical bands.

6. single-allocation planar bands map correctly.

7. non-zero byteOffset is handled correctly.

8. invalid byteOffset is rejected.

9. misaligned T base is rejected.

10. non-divisible byte strides are rejected.

11. signed negative byte strides convert correctly.

12. stride conversion overflow is rejected.

13. final affine footprint outside the resource is rejected.

14. @safe code cannot forge raw ResourceEntry ownership.

15. the public token does not expose release callback/context state.

16. all existing lifetime compile probes remain green.

## C6.1 implementation: ownership token

C6.1 implements the first layer of this design:

```text
raw malloc allocation
        |
        | @system explicit adoption
        v
OwnedByteResource
```

Implemented invariants:

- OwnedByteResource is move-only.
- An armed token carries exactly one release obligation.
- Destruction releases that obligation exactly once.
- Moving transfers the obligation.
- Relinquishing to package-internal raw construction disarms the token.
- The public malloc-compatible adoption boundary is @system.
- ResourceEntry and ReleaseFn remain outside the public imagery.raster API.
- Raw callback/context adoption remains package-internal and @system.

C6.1 deliberately does not yet implement:

- PlaneByteLayout;
- byte-stride conversion;
- RasterLease import;
- multiple physical resources;
- borrowed storage.

Those belong to later C6 implementation steps.

## C6.1 adoption-target semantics

OwnedByteResource adoption uses a `ref` target, never an `out` target.

This is an ownership requirement rather than a stylistic API choice.

D initializes an `out` argument to `T.init` when the function is entered.
That operation is unsuitable for an RAII ownership token because an existing
release obligation must never be erased by resetting the token state.

The adoption rule is therefore:

```text
empty target + valid candidate
    -> adopt candidate

armed target
    -> reject
    -> existing target unchanged
    -> candidate remains caller-owned

invalid candidate
    -> reject
    -> target unchanged
```

Adoption never means "replace".

A caller that intentionally wants to replace an owned resource must first end
or explicitly transfer the old ownership obligation and only then perform a
new adoption.

This keeps every ownership transition explicit and exact-once.
