/++
    Internal execution-layout classification for resident raster planes.

    This module classifies already validated PlaneDescriptor/Region2D metadata
    into progressively stronger execution layouts.

    Classification is metadata-only:

    - no pixel pointer is formed;
    - no storage is dereferenced;
    - no ownership or lifetime capability is created;
    - no execution-library type is exposed.

    Mir adaptation belongs to the later execution-adapter layer.
+/
module imagery.raster.internal.execution_layout;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;


/++
    Strongest generic two-dimensional execution layout available for one
    logical plane of one concrete RasterView.

    The ordering is conceptual rather than numeric:

        Universal -> Canonical -> Contiguous

    These types are package-internal and are not part of the public raster API.
+/
package(imagery.raster)
enum PlaneExecutionLayout2D : ubyte
{
    universal,

    canonical,

    contiguous
}


/++
    Execution capabilities derived for one logical plane.

    `linearContiguous1D` describes whether the current two-dimensional storage
    can also be represented as one contiguous logical sample sequence.

    It is a storage capability only. An operation must independently decide
    whether its semantics permit flat one-dimensional execution.

    `flatElementCount` is meaningful only when `linearContiguous1D` is true.
    Otherwise it is zero.
+/
package(imagery.raster)
struct PlaneExecutionTraits
{
    PlaneExecutionLayout2D layout2D;

    bool linearContiguous1D;

    size_t flatElementCount;
}


/++
    Classifies one already validated resident plane.

    Universal:
        Arbitrary signed affine row/sample traversal.

    Canonical:
        Forward unit-stride traversal in logical x:

            sampleStrideElements == 1

        The row stride remains explicit and may be positive, negative, padded,
        or inherited from a wider parent raster.

    Contiguous:
        Canonical plus no gap between rows of the current view.

        For one row, rowStrideElements is irrelevant because no row transition
        occurs.

        For multiple rows, width must be representable as ptrdiff_t and:

            rowStrideElements == cast(ptrdiff_t) region.width

    Empty regions deliberately classify as Universal with no linear 1D
    capability. Later execution adapters must special-case empty views before
    forming any region-origin pixel pointer.
+/
package(imagery.raster)
PlaneExecutionTraits classifyPlaneExecutionLayout(
    scope const ref PlaneDescriptor descriptor,
    Region2D region
)
@safe
pure
nothrow
@nogc
{
    PlaneExecutionTraits result;

    if (region.empty())
    {
        return result;
    }


    /*
     * Canonical requires exact forward unit stride.
     *
     * In particular, sampleStrideElements == -1 remains Universal.
     * Do not use abs() here: ptrdiff_t.min must remain harmless.
     */
    if (descriptor.sampleStrideElements != 1)
    {
        return result;
    }

    result.layout2D =
        PlaneExecutionLayout2D.canonical;


    /*
     * With one logical row there is no inter-row transition, so the stored
     * row stride has no effect on contiguity of the represented view.
     */
    if (region.height != 1)
    {
        /*
         * rowStrideElements is ptrdiff_t.
         *
         * Check representability before converting width. A width of
         * ptrdiff_t.max + 1 is representable as size_t on the supported
         * architectures and an unchecked cast would wrap into ptrdiff_t.min.
         */
        if (
            region.width
            > cast(size_t) ptrdiff_t.max
        )
        {
            return result;
        }

        if (
            descriptor.rowStrideElements
            != cast(ptrdiff_t) region.width
        )
        {
            return result;
        }
    }

    result.layout2D =
        PlaneExecutionLayout2D.contiguous;


    /*
     * The region is known non-empty here, so height is non-zero.
     *
     * Check before multiplying.
     */
    if (
        region.width
        > size_t.max / region.height
    )
    {
        return result;
    }

    result.linearContiguous1D = true;

    result.flatElementCount =
        region.width * region.height;

    return result;
}


unittest
{
    /*
     * Arbitrary affine / interleaved logical band.
     */
    const descriptor = PlaneDescriptor(
        null,
        37,
        3
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 4)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.universal
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * Negative logical x traversal remains Universal.
     */
    const descriptor = PlaneDescriptor(
        null,
        8,
        -1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 4)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.universal
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * Padded unit-stride rows are Canonical but not Contiguous.
     */
    const descriptor = PlaneDescriptor(
        null,
        16,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 4)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * A negative outer stride remains Canonical.
     */
    const descriptor = PlaneDescriptor(
        null,
        -8,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 4)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * Fully contiguous row-major plane.
     */
    const descriptor = PlaneDescriptor(
        null,
        8,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 4)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.contiguous
    );

    assert(traits.linearContiguous1D);
    assert(traits.flatElementCount == 32);
}


unittest
{
    /*
     * Narrow ROI retains its parent's physical row stride.
     */
    const descriptor = PlaneDescriptor(
        null,
        4096,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(100, 20, 512, 200)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * A row-subset ROI retaining the full physical row width stays
     * Contiguous.
     */
    const descriptor = PlaneDescriptor(
        null,
        4096,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 20, 4096, 3)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.contiguous
    );

    assert(traits.linearContiguous1D);
    assert(traits.flatElementCount == 4096 * 3);
}


unittest
{
    /*
     * For one row, rowStrideElements is never traversed.
     *
     * ptrdiff_t.min also proves that classification performs no abs/negation.
     */
    const descriptor = PlaneDescriptor(
        null,
        ptrdiff_t.min,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(7, 11, 8, 1)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.contiguous
    );

    assert(traits.linearContiguous1D);
    assert(traits.flatElementCount == 8);
}


unittest
{
    /*
     * ptrdiff_t.min as sample stride must remain harmless and Universal.
     */
    const descriptor = PlaneDescriptor(
        null,
        8,
        ptrdiff_t.min
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 8, 2)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.universal
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * Regression test for the dangerous unchecked width -> ptrdiff_t cast.
     *
     * On two's-complement targets:
     *
     *     cast(ptrdiff_t)(ptrdiff_t.max + 1) == ptrdiff_t.min
     *
     * Therefore rowStride == ptrdiff_t.min must not accidentally classify
     * this multi-row view as Contiguous.
     */
    const tooWide =
        cast(size_t) ptrdiff_t.max + 1;

    const descriptor = PlaneDescriptor(
        null,
        ptrdiff_t.min,
        1
    );

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, tooWide, 2)
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * A coordinate extent may be individually representable for validated
     * non-empty access while the flattened element count still overflows
     * size_t.
     *
     * With origin 0:
     *
     *     height = ptrdiff_t.max + 1
     *
     * gives:
     *
     *     lastY = ptrdiff_t.max
     *
     * which remains coordinate-representable.
     */
    const descriptor = PlaneDescriptor(
        null,
        2,
        1
    );

    const height =
        cast(size_t) ptrdiff_t.max + 1;

    const traits =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(
                0,
                0,
                2,
                height
            )
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.contiguous
    );

    assert(!traits.linearContiguous1D);
    assert(traits.flatElementCount == 0);
}


unittest
{
    /*
     * Empty views are deliberately conservative and never claim layout
     * capabilities from strides that are never traversed.
     */
    const descriptor = PlaneDescriptor(
        null,
        64,
        1
    );

    const zeroByZero =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(0, 0, 0, 0)
        );

    const zeroByN =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(size_t.max, size_t.max, 0, 7)
        );

    const nByZero =
        classifyPlaneExecutionLayout(
            descriptor,
            Region2D(size_t.max, size_t.max, 7, 0)
        );

    foreach (traits; [zeroByZero, zeroByN, nByZero])
    {
        assert(
            traits.layout2D
            == PlaneExecutionLayout2D.universal
        );

        assert(!traits.linearContiguous1D);
        assert(traits.flatElementCount == 0);
    }
}
