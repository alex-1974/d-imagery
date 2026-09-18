# R0.2 External Storage and Lifetime Findings

The R0.2 probes validated the ownership and borrowing model considered for
imagery-d raster memory.

## Result

`RasterView` can remain fully non-owning.

Retainable storage is represented separately from the view:

```text
RasterStorage
    |
    | SafeRefCounted
    v
RasterLease
    |
    | return/scope lifetime
    v
RasterView
```

Pure borrowed foreign memory without a retain/release contract uses a
scope-limited callback instead:

```text
foreign memory
    |
    v
withBorrowedRaster(...)
    |
    v
scope RasterView
```

## Verified properties

With both DMD 2.111.0 and LDC 1.41.0, using `-preview=dip1000`:

- a local view obtained from a live `RasterLease` is usable in `@safe` code;
- copying a lease retains the storage;
- owned storage is released exactly once after the final lease dies;
- malloc-backed storage works;
- mmap-backed storage works;
- arbitrary decoder-style release callbacks work;
- a view cannot be returned past its lease lifetime;
- a view cannot be assigned to a longer-lived local;
- a borrowed view cannot be stored in a module-global variable;
- a borrowed view cannot be stored in a heap object;
- synchronous mutation through a borrowed view works while the foreign
  buffer remains valid.

## Design consequence

A foreign pointer may become a `RasterLease` only when imagery-d has a
reliable ownership, retain, or release contract.

Otherwise the buffer must remain a synchronous borrow.

The implementation may require small, audited `@trusted` boundaries for:

- converting validated external pointers into typed raster views;
- allowing a view to leave `SafeRefCounted.borrow` while the enclosing
  `RasterLease` retains the owner.

The view itself, image kernels, and normal user-facing operations should
remain `@safe`.

`-preview=dip1000` is part of the assumptions of these experiments.
