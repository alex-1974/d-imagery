# Raster Construction Architecture

## Status

Initial production design for the construction boundary above the completed
read-only raster foundation.

This document defines ownership and failure semantics before public
construction APIs are introduced.

## Coordinate-space prerequisite

Retained construction uses resident descriptor-space geometry.

Global LogicalImage placement is intentionally outside RasterBacking and
RasterView.

See:

```text
docs/architecture/raster-coordinate-model.md
```

This distinction is required for streaming small resident windows from very
large logical images.


## 1. Context

The production raster foundation already provides:

```text
Region2D
PlaneDescriptor
RasterView!T
RasterBacking!T
RasterLease!T
ResourceEntry
validated retained-resource reachability
DIP1000 lifetime protection
```

The remaining question is how physical storage enters that representation.

The construction layer must support several future source classes without
changing RasterView semantics:

```text
library-owned allocation
external retained memory
mapped memory
decoder-owned buffers
cache-owned blocks
pure borrowed memory
```

These sources have different acquisition and release mechanisms, but all
retained forms should converge on the same validated RasterBacking model.

## 2. Architectural rule

Construction and raster semantics remain separate.

```text
source-specific ownership
        |
        v
construction adapter
        |
        v
validated retained representation
        |
        v
RasterBacking!T
        |
        v
RasterLease!T
        |
        v
RasterView!T
```

RasterView must not know whether the bytes came from:

- malloc;
- mmap;
- a decoder;
- a cache;
- an external library;
- another operating-system resource.

That information belongs to resource retention and release.

## 3. Public API boundary

The following types remain implementation details:

```text
ResourceEntry
ReleaseFn
RasterBacking
raw backing-table allocations
```

In particular, a public API must not expose `ResourceEntry[]` as the normal
construction mechanism.

A ResourceEntry contains raw pointers and an opaque release context. Publishing
that representation directly would move too much trusted-state responsibility
to callers.

Public construction APIs should instead express ownership intent explicitly.

## 4. Construction classes

### 4.1 Retained / owned construction

A retained construction produces RasterLease.

Examples include:

```text
library-owned allocation
adopted external allocation
mapped storage
decoder-retained resource
cache-retained resource
```

The construction adapter must provide enough information to eventually create:

```text
ResourceEntry[]
PlaneDescriptor[]
Region2D
```

but these physical details remain below the public semantic API.

### 4.2 Pure borrowed construction

Pure borrowed memory is fundamentally different.

It must not be converted into RasterLease unless some object genuinely retains
the memory.

The intended model is callback/scoped use:

```text
withBorrowedRaster(...)
{
    RasterView view
    ...
}
```

or an equivalent DIP1000-scoped abstraction.

A borrowed pointer plus a no-op release callback is NOT automatically a
retained resource.

## 5. Ownership terminology

Construction distinguishes three states.

### Unowned metadata

Geometry and descriptor specifications may be copied freely before physical
resource ownership has transferred.

### Pending ownership

A construction object has accepted responsibility for releasing physical
resources, but no RasterLease has yet been published.

### Committed ownership

RasterBacking is the sole owner responsible for releasing the registered
physical resources.

```text
external source
      |
      | ownership transfer
      v
pending construction
      |
      | validation + publication
      v
RasterBacking
      |
      v
RasterLease
```

## 6. Transaction rule

Retained construction must behave transactionally.

Once an adopting construction API accepts ownership of a resource, exactly one
component must remain responsible for releasing it.

The required state machine is:

```text
                 validation fails
                /                  \
               v                    |
source --> pending owner -----------+
               |
               | commit succeeds
               v
          RasterBacking
```

The pending owner releases resources when construction fails.

After successful commit, the pending owner is disarmed and RasterBacking
becomes responsible for release.

At no point may both objects believe they own the same resource.

At no point may ownership disappear between them.

## 7. Failure semantics

### Validation failure

A geometric/layout validation failure is expected input failure.

It should be represented explicitly through a structured construction result,
ultimately preserving the information currently available through
BackingValidationResult.

Validation failure must never publish RasterLease.

### Metadata allocation failure

Backing construction requires stable copies of:

```text
ResourceEntry[]
PlaneDescriptor[]
```

These allocations may fail.

The construction implementation must not leak adopted resources if metadata
allocation fails.

### Reference-count store allocation

RasterLease currently uses SafeRefCounted.

SafeRefCounted allocates its own store.

In the current Phobos implementation, the payload move allocates that store
before moving the payload into it. The store-allocation path is `nothrow` and
may fail only through an Error-level allocation failure.

That condition is therefore not represented as an ordinary
RasterConstructionResult failure.

Recoverable construction failures currently cover validation and the
d-imagery-owned metadata allocations.

The public API still does not promise an out-of-memory recovery policy.

## 8. Stable metadata rule

Caller-owned metadata arrays must not become RasterView lifetime dependencies.

Construction must copy physical metadata into stable backing-owned storage:

```text
caller Resource specs ----copy----+
                                  |
caller Plane specs -------copy----+--> RasterBacking-owned tables
```

After successful construction:

- RasterBacking owns the descriptor table;
- RasterBacking owns the resource table;
- RasterView borrows only the stable backing descriptor table;
- caller metadata storage may disappear immediately.

This requirement is mechanically covered by construction tests that overwrite
the caller-side ResourceEntry and PlaneDescriptor tables after successful
construction and then allow their complete scope to end before using the
returned RasterLease.

The retained RasterView must continue to address the correct samples and the
copied ResourceEntry must still release the physical resource exactly once.

This is independent from the lifetime of the actual pixel resources.

## 9. Validation order

The intended retained-construction pipeline is:

```text
1. receive source-specific ownership
2. normalize physical metadata
3. validate logical geometry and physical reachability
4. allocate stable metadata tables
5. copy normalized metadata
6. create retained RasterBacking owner
7. publish RasterLease
```

No RasterView may be published before validation succeeds.

A later implementation may change the exact allocation ordering when necessary
for exception safety, but the externally visible ownership guarantees must
remain equivalent.

## 10. Release callback context

Release callback state is itself lifetime-sensitive.

```text
ReleaseFn(context, base, byteLength)
```

The adapter supplying `context` must guarantee that context remains valid until
the callback runs.

Safe patterns include:

```text
context allocated together with retained resource state
context owned by the same release operation
stable external handle guaranteed to outlive the resource
```

Unsafe construction must not silently accept pointers to shorter-lived stack
state.

Raw callback/context construction therefore belongs behind a trusted or system
boundary.

## 11. Multiple resources

One RasterBacking may retain multiple independent resources.

This is required for:

```text
separately allocated planar bands
composite decoder outputs
mapped segments
future cache-backed representations
```

Construction must not regress to a single-allocation assumption.

One logical plane may reference one retained resource.

Multiple logical planes may also reference the same retained resource, as in
pixel-interleaved RGB/RGBA.

Both topology classes are mechanically covered by construction tests:

```text
planar
    Plane 0 -> Resource A
    Plane 1 -> Resource B
    Plane 2 -> Resource C

pixel-interleaved
    Plane 0 --+
    Plane 1 --+--> Resource A
    Plane 2 --+
```

The planar case verifies independent exact-once releases for all retained
resources.

The shared-resource case verifies that several PlaneDescriptors may address
different affine streams inside one resource while the underlying physical
resource is released only once.

The validator determines address coverage; construction does not infer
one-resource-per-plane semantics.

## 12. Storage layout

Construction must preserve the existing separation:

```text
storage topology
    !=
execution layout
```

The construction layer may describe:

```text
planar
pixel-interleaved
padded rows
negative traversal
arbitrary affine layout
```

but it must not decide SIMD traversal strategy.

Layout classification remains an execution/planner concern.

## 13. Mutable storage

Mutability is not part of this first construction step.

The first retained construction implementation should target the already
validated read-only capability:

```text
RasterLease!T
    |
    v
RasterView!T
```

A later MutableRasterLease / MutableRasterView capability may reuse the same
resource and construction machinery, but writable permission must be validated
separately.

Construction of read-only retained storage must therefore not accidentally
encode assumptions that all backing memory is writable.

## 14. Initial implementation target

The first production implementation should be package-internal.

It should provide one common retained-construction primitive used by tests and
later source-specific adapters.

Conceptually:

```text
candidate retained resources
candidate plane descriptors
Region2D
        |
        v
internal transactional constructor
        |
        +-- validation failure
        |
        +-- metadata allocation failure
        |
        `-- success --> RasterLease!T
```

The exact function/type names are intentionally not frozen by this document.

## 15. Public adapters to add later

Likely future adapters are:

### Owned allocation

The library allocates backing memory itself.

Useful once writable raster capability exists.

### Adopted external resource

Caller transfers ownership of externally allocated storage.

This must use an explicit ownership-transfer abstraction rather than a naked
pointer plus convention.

### Mapped storage

An mmap/platform mapping adapter registers the appropriate unmap/release
operation.

### Decoder-owned storage

Decoder/provider implementations retain their native resource and expose a
release adapter.

### Borrowed storage

Scoped only; does not produce RasterLease unless a real retention mechanism is
provided.

## 16. Non-goals

This construction phase does not yet define:

- source-provider API;
- TIFF/GeoTIFF decoder API;
- cache implementation;
- mmap portability layer;
- MutableRasterView;
- synchronization;
- scheduler;
- operation graph;
- GPU memory;
- Mir execution adapters.

## 17. Core invariants

The construction layer must preserve all of the following:

```text
1. RasterView owns nothing.

2. RasterLease retains everything needed by RasterView.

3. Plane descriptors remain stable for the entire lease lifetime.

4. Every reachable sample lies within at least one retained resource.

5. Multiple independent resources are supported.

6. Multiple planes may share one retained resource.

7. Ownership transfers exactly once.

8. Every adopted physical resource is released exactly once.

9. Failed construction publishes no RasterLease.

10. Borrowed memory is not disguised as retained memory.

11. Raw release callbacks and callback contexts remain behind a trusted/system
    boundary.

12. Storage layout remains independent from execution strategy.
```

## 18. Planned implementation sequence

```text
C1  internal transactional retained constructor
C2  failure-path / exact-once release tests
C3  metadata-copy / caller-lifetime tests
C4  multi-resource and shared-resource construction tests
C5  construction compile/lifetime probes
C6  first source-specific adapter
C7  public API review
```

The public API should be reviewed only after C1-C5 prove that the ownership
model is mechanically sound.

### Construction lifetime compile coverage

C5 adds compiler-level DIP1000 probes around the actual retained-construction
path.

The probes distinguish ownership from borrowing:

```text
constructed RasterLease
        |
        +-- return RasterLease        -> allowed
        |
        +-- borrow RasterView
                |
                +-- local use         -> allowed
                +-- return View       -> rejected
                +-- return ROI        -> rejected
                `-- global escape     -> rejected
```

This complements the original RasterLease lifetime probes by ensuring that the
construction boundary does not weaken the borrow relationship.

## Raw construction safety boundary

The package-internal retained-construction primitive is deliberately `@system`.

This is not because its normal implementation is expected to perform unchecked
memory accesses directly. It is because raw construction accepts ownership
claims that cannot be proven from the supplied metadata alone.

In particular, the primitive cannot mechanically prove:

- that an opaque `releaseContext` remains alive until the eventual release;
- that an external owner has really transferred the release obligation;
- that source bytes semantically represent the declared sample type;
- that an external callback obeys its documented ownership contract.

A raw ResourceEntry therefore must not become an implicitly safe construction
capability.

Source-specific adapters cross this boundary explicitly after establishing
their own source-specific invariants.

The intended layering is:

```text
public/source-specific API
        |
        | validates representation
        | establishes ownership/context lifetime
        v
small audited adapter boundary
        |
        | explicit @trusted / @system transition
        v
package raw retained construction (@system)
        |
        v
RasterLease
        |
        v
borrowed RasterView
```

## Raster sample representation

Raster samples are raw resident values.

The core therefore restricts T to representation-simple types:

- unqualified;
- POD;
- without pointer/reference-like indirections.

This permits ordinary numeric samples and simple POD pixel aggregates while
excluding types whose copy, destruction, GC reachability, or ownership
semantics cannot be reconstructed safely from arbitrary retained bytes.

The restriction is represented by `isRasterSampleType!T`.


## C6 external retained import

The first public retained-storage adapter is specified separately:

```text
docs/architecture/raster-external-import.md
```

The design introduces an ownership token above raw ResourceEntry and keeps
external byte-oriented layout conversion outside the core PlaneDescriptor
representation.

The initial adapter deliberately supports one physical resource with multiple
logical planes. Multi-resource adoption remains a later extension.
