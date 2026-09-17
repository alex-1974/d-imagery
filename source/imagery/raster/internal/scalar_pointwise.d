/++
    Scalar pointwise reference kernels.

    E3c establishes the first source-to-target execution baseline:

        read-only source -> writable contiguous target

    The initial operation is an exact same-type copy. Numeric conversion,
    overlap handling, SIMD, parallel execution, and public operation semantics
    are deliberately deferred.

    Shape mismatch is detected before the first target write.
+/
module imagery.raster.internal.scalar_pointwise;

import mir.ndslice :
    Canonical,
    Contiguous,
    Slice,
    Universal;


/++
    Shared two-dimensional scalar copy implementation.

    The caller-facing entry points constrain source and target to the same
    sample type. This helper only performs shape validation and traversal.
+/
private
bool scalarCopy2DImpl(Source, Target)(
    scope Source source,
    scope Target target
)
@safe
pure
nothrow
@nogc
{
    if (
        source.length!0 != target.length!0
        || source.length!1 != target.length!1
    )
    {
        return false;
    }

    foreach (y; 0 .. source.length!0)
    {
        foreach (x; 0 .. source.length!1)
        {
            target[y, x] =
                source[y, x];
        }
    }

    return true;
}


/++
    Shared flat scalar copy implementation.
+/
private
bool scalarCopy1DImpl(Source, Target)(
    scope Source source,
    scope Target target
)
@safe
pure
nothrow
@nogc
{
    if (source.length!0 != target.length!0)
        return false;

    foreach (i; 0 .. source.length!0)
    {
        target[i] =
            source[i];
    }

    return true;
}


/++
    Copies a Universal 2D source into a contiguous 2D target.

    Source/target overlap is not part of the E3c correctness contract.
+/
package(imagery.raster)
bool scalarCopyUniversalToContiguous2D(T)(
    scope Slice!(const(T)*, 2, Universal) source,
    scope Slice!(T*, 2, Contiguous) target
)
@safe
pure
nothrow
@nogc
{
    return scalarCopy2DImpl(
        source,
        target
    );
}


/++
    Copies a Canonical 2D source into a contiguous 2D target.

    Source/target overlap is not part of the E3c correctness contract.
+/
package(imagery.raster)
bool scalarCopyCanonicalToContiguous2D(T)(
    scope Slice!(const(T)*, 2, Canonical) source,
    scope Slice!(T*, 2, Contiguous) target
)
@safe
pure
nothrow
@nogc
{
    return scalarCopy2DImpl(
        source,
        target
    );
}


/++
    Copies a contiguous 2D source into a contiguous 2D target.

    Source/target overlap is not part of the E3c correctness contract.
+/
package(imagery.raster)
bool scalarCopyContiguous2D(T)(
    scope Slice!(const(T)*, 2, Contiguous) source,
    scope Slice!(T*, 2, Contiguous) target
)
@safe
pure
nothrow
@nogc
{
    return scalarCopy2DImpl(
        source,
        target
    );
}


/++
    Copies a flat contiguous source into a flat contiguous target.

    This path is the initial E3c baseline most directly suited to later
    vectorization/code-generation inspection.
+/
package(imagery.raster)
bool scalarCopyContiguous1D(T)(
    scope Slice!(const(T)*, 1, Contiguous) source,
    scope Slice!(T*, 1, Contiguous) target
)
@safe
pure
nothrow
@nogc
{
    return scalarCopy1DImpl(
        source,
        target
    );
}


version (unittest)
{

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.internal.mir_adapter :
    asMirCanonical,
    asMirContiguous,
    asMirContiguousFlat,
    asMirUniversal;

import imagery.raster.internal.mir_target_adapter :
    asMirTargetContiguous,
    asMirTargetContiguousFlat;

import imagery.raster.internal.target :
    tryBorrowContiguousTarget;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/*
 * Universal/interleaved source -> contiguous target.
 *
 * Logical source samples:
 *
 *      0  3  6  9
 *     12 15 18 21
 */
unittest
{
    ubyte[24] sourceStorage;

    foreach (i; 0 .. sourceStorage.length)
    {
        sourceStorage[i] =
            cast(ubyte) i;
    }

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            12,
            3
        )
    ];

    auto sourceView =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                2
            )
        );

    ubyte[8] targetStorage;

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage[],
            4,
            2,
            success
        );

    assert(success);

    assert(
        scalarCopyUniversalToContiguous2D(
            asMirUniversal(
                sourceView,
                0
            ),
            asMirTargetContiguous(
                targetView
            )
        )
    );

    const ubyte[8] expected =
        [0, 3, 6, 9, 12, 15, 18, 21];

    assert(targetStorage == expected);
}


/*
 * Negative-row-stride Canonical source -> contiguous target.
 */
unittest
{
    ubyte[12] sourceStorage =
    [
         0,  1,  2,  3,
        10, 11, 12, 13,
        20, 21, 22, 23
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            &sourceStorage[8],
            -4,
            1
        )
    ];

    auto sourceView =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    ubyte[12] targetStorage;

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage[],
            4,
            3,
            success
        );

    assert(success);

    assert(
        scalarCopyCanonicalToContiguous2D(
            asMirCanonical(
                sourceView,
                0
            ),
            asMirTargetContiguous(
                targetView
            )
        )
    );

    const ubyte[12] expected =
    [
        20, 21, 22, 23,
        10, 11, 12, 13,
         0,  1,  2,  3
    ];

    assert(targetStorage == expected);
}


/*
 * Contiguous 2D source -> contiguous 2D target.
 */
unittest
{
    ubyte[6] sourceStorage =
        [1, 2, 3, 4, 5, 6];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            3,
            1
        )
    ];

    auto sourceView =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                3,
                2
            )
        );

    ubyte[6] targetStorage;

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage[],
            3,
            2,
            success
        );

    assert(success);

    assert(
        scalarCopyContiguous2D(
            asMirContiguous(
                sourceView,
                0
            ),
            asMirTargetContiguous(
                targetView
            )
        )
    );

    assert(targetStorage == sourceStorage);
}


/*
 * Flat contiguous source -> flat contiguous target.
 */
unittest
{
    ushort[6] sourceStorage =
        [100, 200, 300, 400, 500, 600];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            3,
            1
        )
    ];

    auto sourceView =
        makeRasterViewAssumeValidated!ushort(
            descriptors[],
            Region2D(
                0,
                0,
                3,
                2
            )
        );

    ushort[6] targetStorage;

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage[],
            3,
            2,
            success
        );

    assert(success);

    assert(
        scalarCopyContiguous1D(
            asMirContiguousFlat(
                sourceView,
                0
            ),
            asMirTargetContiguousFlat(
                targetView
            )
        )
    );

    assert(targetStorage == sourceStorage);
}


/*
 * Shape mismatch must fail before the first target write.
 */
unittest
{
    ubyte[4] sourceStorage =
        [1, 2, 3, 4];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            2,
            1
        )
    ];

    auto sourceView =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                2,
                2
            )
        );

    ubyte[3] targetStorage =
        [91, 92, 93];

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage[],
            3,
            1,
            success
        );

    assert(success);

    assert(
        !scalarCopyContiguous2D(
            asMirContiguous(
                sourceView,
                0
            ),
            asMirTargetContiguous(
                targetView
            )
        )
    );

    assert(
        targetStorage
        == [91, 92, 93]
    );
}


/*
 * Empty source and target with matching logical dimensions succeed without
 * dereferencing either null iterator.
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

    auto sourceView =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                size_t.max,
                size_t.max,
                0,
                7
            )
        );

    ubyte[] targetStorage;

    bool success;

    auto targetView =
        tryBorrowContiguousTarget(
            targetStorage,
            0,
            7,
            success
        );

    assert(success);

    assert(
        scalarCopyUniversalToContiguous2D(
            asMirUniversal(
                sourceView,
                0
            ),
            asMirTargetContiguous(
                targetView
            )
        )
    );
}

}
