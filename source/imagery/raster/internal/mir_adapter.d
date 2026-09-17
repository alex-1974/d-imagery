/++
    Internal Mir execution adapters for RasterView.

    RasterView remains the semantic raster abstraction.

    Mir ndslice is used only as an internal execution representation for
    already classified and validated resident planes.

    All Mir element pointers are const(T)* because RasterView is read-only.

    Raw region-origin pointer formation remains inside RasterView's narrow
    trusted package boundary. This module itself performs no raw pointer
    arithmetic.
+/
module imagery.raster.internal.mir_adapter;

import imagery.raster.internal.execution_layout :
    PlaneExecutionLayout2D,
    PlaneExecutionTraits;

import imagery.raster.view :
    RasterView;

import mir.ndslice :
    Canonical,
    Contiguous,
    Slice,
    Universal;


/++
    Internal arbitrary-affine 2D execution representation.
+/
package(imagery.raster)
alias MirUniversalPlane(T) =
    Slice!(const(T)*, 2, Universal);


/++
    Internal forward-unit-x-stride 2D execution representation.
+/
package(imagery.raster)
alias MirCanonicalPlane(T) =
    Slice!(const(T)*, 2, Canonical);


/++
    Internal fully contiguous 2D execution representation.
+/
package(imagery.raster)
alias MirContiguousPlane(T) =
    Slice!(const(T)*, 2, Contiguous);


/++
    Internal flat contiguous execution representation.

    This does not change RasterView's semantic geometry. It is only an
    execution fast path for operations whose semantics independently permit
    flattening.
+/
package(imagery.raster)
alias MirContiguousFlat(T) =
    Slice!(const(T)*, 1, Contiguous);


/++
    Returns the validated execution traits for one plane.

    Invalid plane indices are programmer errors at this internal layer.
+/
private
PlaneExecutionTraits requirePlaneExecutionTraits(T)(
    scope RasterView!T view,
    size_t planeIndex
)
@safe
pure
nothrow
@nogc
{
    PlaneExecutionTraits traits;

    const ok =
        view.tryPlaneExecutionTraits(
            planeIndex,
            traits
        );

    assert(ok);

    return traits;
}


/++
    Returns the signed physical plane strides required by Mir Universal or
    Canonical.

    Invalid plane indices are programmer errors at this internal layer.
+/
private
void requirePlaneStrides(T)(
    scope RasterView!T view,
    size_t planeIndex,
    out ptrdiff_t rowStrideElements,
    out ptrdiff_t sampleStrideElements
)
@safe
pure
nothrow
@nogc
{
    const ok =
        view.tryExecutionPlaneStrides(
            planeIndex,
            rowStrideElements,
            sampleStrideElements
        );

    assert(ok);
}


/++
    Adapts one plane to Mir Universal.

    This is the generic execution representation and supports arbitrary
    validated signed row/sample strides.

    Empty RasterViews are represented by a zero-area slice whose iterator is
    null. No region-origin pointer arithmetic is performed for that case.

    The returned slice is lifetime-bound to the source RasterView.
+/
package(imagery.raster)
MirUniversalPlane!T asMirUniversal(T)(
    return scope RasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    /*
     * Validate the plane index through the normal internal control path.
     */
    cast(void)
        requirePlaneExecutionTraits(
            view,
            planeIndex
        );

    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;

    requirePlaneStrides(
        view,
        planeIndex,
        rowStrideElements,
        sampleStrideElements
    );

    const base =
        view.executionRegionBase(
            planeIndex
        );

    return MirUniversalPlane!T(
        [
            view.height,
            view.width
        ],
        [
            rowStrideElements,
            sampleStrideElements
        ],
        base
    );
}


/++
    Adapts one plane to Mir Canonical.

    Preconditions:

        layout2D == Canonical
        or
        layout2D == Contiguous

    The logical x dimension is therefore forward unit-stride. The explicit
    row stride may still be padded or negative.
+/
package(imagery.raster)
MirCanonicalPlane!T asMirCanonical(T)(
    return scope RasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    const traits =
        requirePlaneExecutionTraits(
            view,
            planeIndex
        );

    assert(
        traits.layout2D
        != PlaneExecutionLayout2D.universal
    );

    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;

    requirePlaneStrides(
        view,
        planeIndex,
        rowStrideElements,
        sampleStrideElements
    );

    assert(sampleStrideElements == 1);

    const base =
        view.executionRegionBase(
            planeIndex
        );

    return MirCanonicalPlane!T(
        [
            view.height,
            view.width
        ],
        [
            rowStrideElements
        ],
        base
    );
}


/++
    Adapts one plane to fully contiguous Mir 2D representation.
+/
package(imagery.raster)
MirContiguousPlane!T asMirContiguous(T)(
    return scope RasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    const traits =
        requirePlaneExecutionTraits(
            view,
            planeIndex
        );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.contiguous
    );

    const base =
        view.executionRegionBase(
            planeIndex
        );

    return MirContiguousPlane!T(
        [
            view.height,
            view.width
        ],
        base
    );
}


/++
    Adapts one plane to a flat contiguous Mir representation.

    The E1 classifier has already checked width*height representability.

    Whether an image operation is semantically allowed to flatten is a
    separate later-layer decision.
+/
package(imagery.raster)
MirContiguousFlat!T asMirContiguousFlat(T)(
    return scope RasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    const traits =
        requirePlaneExecutionTraits(
            view,
            planeIndex
        );

    assert(traits.linearContiguous1D);

    const base =
        view.executionRegionBase(
            planeIndex
        );

    return MirContiguousFlat!T(
        [
            traits.flatElementCount
        ],
        base
    );
}


version (unittest)
{

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


unittest
{
    /*
     * Universal adapter for one logical channel of an interleaved stream.
     */

    ubyte[24] storage;

    foreach (i; 0 .. storage.length)
    {
        storage[i] =
            cast(ubyte) i;
    }

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            12,
            3
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                2
            )
        );

    auto plane =
        asMirUniversal(
            view,
            0
        );

    assert(plane[0, 0] == 0);
    assert(plane[0, 1] == 3);
    assert(plane[0, 3] == 9);

    assert(plane[1, 0] == 12);
    assert(plane[1, 3] == 21);

    static assert(
        is(typeof(plane[0, 0]) == const(ubyte))
    );

    static assert(
        !__traits(
            compiles,
            plane[0, 0] = 255
        )
    );
}


unittest
{
    /*
     * Canonical adapter with a negative outer stride.
     */

    ubyte[12] storage =
    [
         0,  1,  2,  3,
        10, 11, 12, 13,
        20, 21, 22, 23
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            &storage[8],
            -4,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    PlaneExecutionTraits traits;

    assert(
        view.tryPlaneExecutionTraits(
            0,
            traits
        )
    );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    auto plane =
        asMirCanonical(
            view,
            0
        );

    assert(plane[0, 0] == 20);
    assert(plane[0, 3] == 23);

    assert(plane[1, 0] == 10);
    assert(plane[1, 3] == 13);

    assert(plane[2, 0] == 0);
    assert(plane[2, 3] == 3);
}


unittest
{
    /*
     * Full contiguous 2D and flat adapters.
     */

    ubyte[12] storage =
    [
         0,  1,  2,  3,
        10, 11, 12, 13,
        20, 21, 22, 23
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    auto plane2D =
        asMirContiguous(
            view,
            0
        );

    auto plane1D =
        asMirContiguousFlat(
            view,
            0
        );

    assert(plane2D[0, 0] == 0);
    assert(plane2D[2, 3] == 23);

    assert(plane1D.length!0 == 12);

    assert(plane1D[0] == 0);
    assert(plane1D[4] == 10);
    assert(plane1D[11] == 23);
}


unittest
{
    /*
     * Non-zero RasterView origin must move the Mir iterator to the first
     * logical sample of the current view, while preserving parent strides.
     */

    ubyte[20] storage =
    [
         0,  1,  2,  3,  4,
        10, 11, 12, 13, 14,
        20, 21, 22, 23, 24,
        30, 31, 32, 33, 34
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            5,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                1,
                1,
                3,
                2
            )
        );

    PlaneExecutionTraits traits;

    assert(
        view.tryPlaneExecutionTraits(
            0,
            traits
        )
    );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.canonical
    );

    auto plane =
        asMirCanonical(
            view,
            0
        );

    assert(plane[0, 0] == 11);
    assert(plane[0, 1] == 12);
    assert(plane[0, 2] == 13);

    assert(plane[1, 0] == 21);
    assert(plane[1, 2] == 23);
}


unittest
{
    /*
     * Empty RasterViews must not form a pointer to their descriptor-space
     * origin.

     * Deliberately use extreme origin coordinates and extreme strides that
     * would be invalid to evaluate for a reachable sample.
     */

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            null,
            ptrdiff_t.min,
            ptrdiff_t.min
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                size_t.max,
                size_t.max,
                0,
                7
            )
        );

    assert(view.empty);

    auto plane =
        asMirUniversal(
            view,
            0
        );

    assert(plane.length!0 == 7);
    assert(plane.length!1 == 0);
}

}
