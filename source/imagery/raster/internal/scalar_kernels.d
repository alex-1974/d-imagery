/++
    Scalar reference kernels for raster execution views.

    These kernels operate only on internal Mir execution representations.

    They deliberately do not:

    - choose an execution layout;
    - dispatch from RasterView;
    - define public image-operation semantics;
    - introduce SIMD or parallel execution.

    Their purpose is to provide a simple correctness baseline shared by the
    execution layouts established in E1/E2.
+/
module imagery.raster.internal.scalar_kernels;

import mir.ndslice :
    Canonical,
    Contiguous,
    Slice,
    Universal;


/++
    Shared two-dimensional scalar summation implementation.

    Accumulator is explicit so this low-level execution layer does not impose
    hidden widening, overflow, or floating-point accumulation policy.
+/
private
Accumulator scalarSum2DImpl(Accumulator, Plane)(
    scope Plane plane
)
@safe
pure
nothrow
@nogc
{
    Accumulator total =
        cast(Accumulator) 0;

    foreach (y; 0 .. plane.length!0)
    {
        foreach (x; 0 .. plane.length!1)
        {
            total +=
                cast(Accumulator)
                    plane[y, x];
        }
    }

    return total;
}


/++
    Scalar reference sum for arbitrary affine 2D execution layout.
+/
package(imagery.raster)
Accumulator scalarSumUniversal2D(Accumulator, T)(
    scope Slice!(const(T)*, 2, Universal) plane
)
@safe
pure
nothrow
@nogc
{
    return scalarSum2DImpl!Accumulator(
        plane
    );
}


/++
    Scalar reference sum for Canonical 2D execution layout.
+/
package(imagery.raster)
Accumulator scalarSumCanonical2D(Accumulator, T)(
    scope Slice!(const(T)*, 2, Canonical) plane
)
@safe
pure
nothrow
@nogc
{
    return scalarSum2DImpl!Accumulator(
        plane
    );
}


/++
    Scalar reference sum for fully contiguous 2D execution layout.

    E4 may later replace this implementation with a layout-specific fast path
    while retaining the same result contract.
+/
package(imagery.raster)
Accumulator scalarSumContiguous2D(Accumulator, T)(
    scope Slice!(const(T)*, 2, Contiguous) plane
)
@safe
pure
nothrow
@nogc
{
    return scalarSum2DImpl!Accumulator(
        plane
    );
}


/++
    Scalar reference sum for a flat contiguous execution layout.

    Flattening eligibility has already been proven by E1 and remains distinct
    from an operation's semantic decision to use this representation.
+/
package(imagery.raster)
Accumulator scalarSumContiguous1D(Accumulator, T)(
    scope Slice!(const(T)*, 1, Contiguous) plane
)
@safe
pure
nothrow
@nogc
{
    Accumulator total =
        cast(Accumulator) 0;

    foreach (i; 0 .. plane.length!0)
    {
        total +=
            cast(Accumulator)
                plane[i];
    }

    return total;
}


version (unittest)
{

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.internal.execution_layout :
    PlaneExecutionLayout2D,
    PlaneExecutionTraits;

import imagery.raster.internal.mir_adapter :
    asMirCanonical,
    asMirContiguous,
    asMirContiguousFlat,
    asMirUniversal;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/*
 * All four execution representations of one contiguous plane must produce
 * the same scalar result.
 */
unittest
{
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

    const universal =
        scalarSumUniversal2D!ulong(
            asMirUniversal(
                view,
                0
            )
        );

    const canonical =
        scalarSumCanonical2D!ulong(
            asMirCanonical(
                view,
                0
            )
        );

    const contiguous2D =
        scalarSumContiguous2D!ulong(
            asMirContiguous(
                view,
                0
            )
        );

    const contiguous1D =
        scalarSumContiguous1D!ulong(
            asMirContiguousFlat(
                view,
                0
            )
        );

    enum ulong expected = 138;

    assert(universal == expected);
    assert(canonical == expected);
    assert(contiguous2D == expected);
    assert(contiguous1D == expected);
}


/*
 * Narrow ROI of a wider contiguous parent is Canonical, not Contiguous.
 *
 * Expected samples:
 *
 *     11 12 13
 *     21 22 23
 */
unittest
{
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

    const result =
        scalarSumCanonical2D!ulong(
            asMirCanonical(
                view,
                0
            )
        );

    assert(result == 102);
}


/*
 * Interleaved logical channel remains Universal.
 *
 * Physical samples selected by sampleStride == 3:
 *
 *     0  3  6  9
 *    12 15 18 21
 */
unittest
{
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

    PlaneExecutionTraits traits;

    assert(
        view.tryPlaneExecutionTraits(
            0,
            traits
        )
    );

    assert(
        traits.layout2D
        == PlaneExecutionLayout2D.universal
    );

    const result =
        scalarSumUniversal2D!ulong(
            asMirUniversal(
                view,
                0
            )
        );

    assert(result == 84);
}


/*
 * Negative outer stride must preserve logical scalar semantics.
 */
unittest
{
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

    const result =
        scalarSumCanonical2D!ulong(
            asMirCanonical(
                view,
                0
            )
        );

    assert(result == 138);
}


/*
 * Empty execution views must produce the additive identity without touching
 * their null iterator.
 */
unittest
{
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

    const integerResult =
        scalarSumUniversal2D!ulong(
            asMirUniversal(
                view,
                0
            )
        );

    const floatingResult =
        scalarSumUniversal2D!double(
            asMirUniversal(
                view,
                0
            )
        );

    assert(integerResult == 0);
    assert(floatingResult == 0.0);
}


/*
 * Accumulator choice is deliberately supplied by the caller.
 */
unittest
{
    float[4] storage =
    [
        0.5f,
        1.5f,
        2.5f,
        3.5f
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            2,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                2,
                2
            )
        );

    const result =
        scalarSumContiguous1D!double(
            asMirContiguousFlat(
                view,
                0
            )
        );

    assert(result == 8.0);
}

}
