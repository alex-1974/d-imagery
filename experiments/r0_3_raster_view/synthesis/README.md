# R0.3 Core-Type Synthesis Probes

This directory contains focused compile-time probes for the final R0.3
core-type synthesis.

They are not production implementations.

## Mutability capability model

The selected model separates:

- physical plane description;
- read capability;
- write capability;
- resource lifetime.

The physical descriptor is access-neutral:

```d
struct PlaneDescriptor
{
    const(void)* base;
    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;
}
```

Read and write access are represented by distinct view types:

```text
RasterView!T
    read-only pixel capability

MutableRasterView!T
    writable pixel capability
```

Both borrow the same stable descriptor block.

A writable view can be downgraded to a read-only view in O(1) without
rebuilding descriptors or copying pixel data.

The reverse capability conversion is not provided.

## Probes

`mutability_positive.d`

Validates with DMD and LDC that:

- `MutableRasterView!T.planeBase()` yields `T*`;
- mutable pixel writes compile;
- `readOnly()` yields `RasterView!T`;
- `RasterView!T.planeBase()` yields `const(T)*`;
- mutable ROI remains mutable;
- read-only ROI remains read-only;
- all transformations reuse the same descriptor block.

`mutability_negative_write.d`

Must fail because writing through a read-only view attempts to modify a
`const(T)` value.

`mutability_negative_upgrade.d`

Must fail because a `RasterView!T` cannot implicitly convert to
`MutableRasterView!T`.

## Architectural interpretation

`PlaneDescriptor` does not grant write authority.

Writable access is granted only by a validated trusted construction path,
ultimately associated with writable retained storage.

Therefore:

```text
physical metadata
      |
      +---------------------------+
      |                           |
      v                           v
RasterView!T              MutableRasterView!T
read capability           write capability
      ^                           |
      +---------------------------+
             downgrade only
```

DIP1000 remains responsible for borrow lifetime.

The trusted backing/lease boundary is responsible for storage validity and
for whether writable capability may be created.

Mutable capability is not an exclusive-borrow or concurrency guarantee.
Aliasing and synchronization remain separate execution-policy concerns.
