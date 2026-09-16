# Raster Coordinate Model

## Status

Production architecture decision.

## Core rule

RasterView describes resident raster storage.

It does not carry the global placement of that storage inside a LogicalImage.

The two coordinate spaces are deliberately separate.

```text
LogicalImage
    |
    | global Region2D request
    | e.g. (100000, 200000, 512, 512)
    v
provider / cache
    |
    | resolves or decodes resident storage
    v
RasterLease / RasterView
    |
    | resident descriptor coordinates
    | commonly (0, 0, 512, 512)
    v
execution adapters / kernels
```

## Region2D

Region2D is a geometry value type.

It does not intrinsically mean either:

- global LogicalImage coordinates; or
- resident RasterView coordinates.

Its owner defines the coordinate-space semantics.

For example:

```text
RegionRequest.region
    -> global LogicalImage coordinate space

RasterView.region
    -> resident descriptor coordinate space
```

The same small value type can therefore be reused without coupling the two
layers.

## PlaneDescriptor

PlaneDescriptor.base represents resident descriptor coordinate `(0, 0)`.

Addressing is:

```text
descriptorX = view.region.x + localViewX
descriptorY = view.region.y + localViewY

offset =
      descriptorY * rowStrideElements
    + descriptorX * sampleStrideElements
```

No LogicalImage/global coordinate participates in this pointer arithmetic.

## Full resident views

A provider or cache will commonly publish a resident block as:

```text
Region2D(
    0,
    0,
    residentWidth,
    residentHeight
)
```

This is not a universal requirement.

A retained resource may contain:

- padding;
- halo;
- alignment prefix;
- a larger cached block than the visible view.

In those cases a valid RasterView may begin at a non-zero descriptor-space
coordinate.

Example:

```text
physical retained block
+----------------------+
| padding / halo       |
|   +--------------+   |
|   | visible view |   |
|   +--------------+   |
+----------------------+

visible resident region:
    Region2D(1, 1, width, height)
```

The important rule is that these coordinates remain resident/storage
coordinates, not global LogicalImage placement.

## ROI

RasterView.tryRoi() resolves a child inside the same resident descriptor
coordinate system.

ROI therefore remains:

- O(1);
- descriptor-sharing;
- allocation-free;
- storage-non-owning.

For a full resident view:

```text
Region2D(0, 0, 512, 512)
```

a relative ROI:

```text
Region2D(10, 20, 100, 80)
```

resolves to resident descriptor coordinates:

```text
Region2D(10, 20, 100, 80)
```

A nested ROI continues in the same descriptor coordinate system.

## Global placement

Global placement belongs above RasterView.

A future request/cache/task representation may conceptually contain:

```text
globalRegion:
    Region2D(100000, 200000, 512, 512)

resident:
    RasterLease!T
```

or equivalent metadata.

The exact higher-level type is intentionally not frozen here.

## Why global coordinates are not stored in RasterView

Keeping global placement outside RasterView has several advantages:

1. RasterView remains a compact execution-facing value.

2. Pointer arithmetic depends only on resident storage geometry.

3. Very large LogicalImage coordinates do not artificially constrain
   ptrdiff_t-based memory offsets.

4. Mir or other execution adapters naturally consume resident coordinates.

5. The same resident block can potentially be reused for different
   higher-level scheduling or cache metadata without changing its physical
   representation.

6. Provider/source tiling remains separate from processing regions.

## Streaming example

A logical image may be extremely large:

```text
LogicalImage extent:
    500000 x 500000
```

A request may ask for:

```text
global Region2D:
    x      = 100000
    y      = 200000
    width  = 4
    height = 3
```

The provider may materialize only twelve ubyte samples:

```text
resident allocation:
    12 bytes

RasterView.region:
    Region2D(0, 0, 4, 3)
```

Sample `(3, 2)` therefore addresses resident byte 11.

There is no physical prefix corresponding to the first 100000 columns or
200000 rows of the LogicalImage.

## Invariant

The architecture therefore keeps:

```text
LogicalImage placement
        !=
RasterView resident geometry
        !=
PlaneDescriptor physical strides
```

This is consistent with the broader d-imagery invariant:

```text
ProviderTile != CacheBlock != Region != ProcessingTask
```

None of these concepts is permitted to collapse merely because a particular
source format happens to use tiles.
