/++
    Internal copy dispatch and source/target alias-relation checks.

    Source/target non-overlap is a relation between one concrete source plane
    and one concrete target. It is deliberately not represented as a property
    of RasterTargetPlane and is not accepted as an unchecked caller assertion.

    E4.3a establishes only the checked semantic path. The successful
    non-overlapping case still executes the scalar E3c reference kernel.

    Compiler-specific no-alias specialization belongs to a later step.
+/
module imagery.raster.internal.copy_dispatch;

import imagery.raster.internal.execution_layout :
    PlaneExecutionTraits;

import imagery.raster.internal.mir_adapter :
    asMirContiguousFlat;

import imagery.raster.internal.mir_target_adapter :
    asMirTargetContiguousFlat;

import imagery.raster.internal.scalar_pointwise :
    scalarCopyContiguous1D;

import imagery.raster.internal.target :
    RasterTargetPlane;

import imagery.raster.view :
    RasterView;


/++
    Failure category for checked non-overlapping contiguous copy.
+/
package(imagery.raster)
enum NonOverlappingCopyError : ubyte
{
    none,

    invalidPlaneIndex,

    shapeMismatch,

    unsupportedExecution,

    overlapDetected,

    addressRangeUnrepresentable
}


/++
    Result of checked non-overlapping contiguous copy.

    `.init` deliberately represents failure rather than success.
+/
package(imagery.raster)
struct NonOverlappingCopyResult
{
    NonOverlappingCopyError error =
        NonOverlappingCopyError.addressRangeUnrepresentable;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == NonOverlappingCopyError.none;
    }
}


private
NonOverlappingCopyResult copySuccess()
@safe
pure
nothrow
@nogc
{
    NonOverlappingCopyResult result;

    result.error =
        NonOverlappingCopyError.none;

    return result;
}


private
NonOverlappingCopyResult copyFailure(
    NonOverlappingCopyError error
)
@safe
pure
nothrow
@nogc
{
    NonOverlappingCopyResult result;

    result.error =
        error;

    return result;
}


/*
 * Relation between two non-empty flat byte-address intervals.
 */
private
enum PhysicalRangeRelation : ubyte
{
    overlapping,

    nonOverlapping,

    unrepresentable
}


/++
    Classifies two equally sized, non-empty contiguous T ranges.

    This is the only E4.3a trusted boundary.

    Pointer values are converted to integer addresses so half-open physical
    byte intervals can be compared:

        [sourceStart, sourceEnd)
        [targetStart, targetEnd)

    The project already uses the same flat-address representation inside its
    retained-resource validation boundary.

    No pointer is dereferenced here.
+/
private
PhysicalRangeRelation classifyPhysicalRangeRelation(T)(
    scope const(T)* sourceBase,
    scope T* targetBase,
    size_t elementCount
)
@trusted
nothrow
@nogc
{
    assert(sourceBase !is null);
    assert(targetBase !is null);
    assert(elementCount != 0);

    if (
        elementCount
        > size_t.max / T.sizeof
    )
    {
        return PhysicalRangeRelation.unrepresentable;
    }

    const byteLength =
        elementCount * T.sizeof;

    const sourceStart =
        cast(size_t) sourceBase;

    const targetStart =
        cast(size_t) targetBase;

    if (
        byteLength > size_t.max - sourceStart
        || byteLength > size_t.max - targetStart
    )
    {
        return PhysicalRangeRelation.unrepresentable;
    }

    const sourceEnd =
        sourceStart + byteLength;

    const targetEnd =
        targetStart + byteLength;

    if (
        sourceEnd <= targetStart
        || targetEnd <= sourceStart
    )
    {
        return PhysicalRangeRelation.nonOverlapping;
    }

    return PhysicalRangeRelation.overlapping;
}


/++
    Copies one source plane into a contiguous target only after proving that
    their complete flat contiguous physical ranges do not overlap.

    The function does not accept a caller-supplied alias assertion.

    Preconditions are established internally in this order:

    - plane index must be valid;
    - source and target logical shapes must match;
    - empty matching shapes succeed without forming physical ranges;
    - the source must provide flat Contiguous 1D execution;
    - physical byte intervals must be representable;
    - source and target intervals must not overlap.

    Failure occurs before the first target write.

    E4.3a deliberately executes the existing scalar E3c copy after the
    non-overlap proof. A later specialization may replace only that final
    execution step without weakening this checked contract.
+/
package(imagery.raster)
NonOverlappingCopyResult tryCopyNonOverlappingContiguous1D(T)(
    scope RasterView!T source,
    size_t planeIndex,
    scope RasterTargetPlane!T target
)
@safe
nothrow
@nogc
{
    PlaneExecutionTraits traits;

    if (
        !source.tryPlaneExecutionTraits(
            planeIndex,
            traits
        )
    )
    {
        return copyFailure(
            NonOverlappingCopyError.invalidPlaneIndex
        );
    }

    if (
        source.width != target.width
        || source.height != target.height
    )
    {
        return copyFailure(
            NonOverlappingCopyError.shapeMismatch
        );
    }

    /*
     * Matching empty shapes contain no reachable samples and therefore no
     * overlapping sample range requiring proof.
     */
    if (source.empty)
    {
        return copySuccess();
    }

    if (!traits.linearContiguous1D)
    {
        return copyFailure(
            NonOverlappingCopyError.unsupportedExecution
        );
    }

    assert(
        traits.flatElementCount
        == target.elementCount
    );

    const sourceBase =
        source.executionRegionBase(
            planeIndex
        );

    auto targetBase =
        target.executionBase();

    assert(sourceBase !is null);
    assert(targetBase !is null);

    final switch (
        classifyPhysicalRangeRelation(
            sourceBase,
            targetBase,
            traits.flatElementCount
        )
    )
    {
        case PhysicalRangeRelation.overlapping:
            return copyFailure(
                NonOverlappingCopyError.overlapDetected
            );

        case PhysicalRangeRelation.nonOverlapping:
        {
            const copied =
                scalarCopyContiguous1D(
                    asMirContiguousFlat(
                        source,
                        planeIndex
                    ),
                    asMirTargetContiguousFlat(
                        target
                    )
                );

            /*
             * Shape equality and flat element-count equality were already
             * established above.
             */
            assert(copied);

            return copySuccess();
        }

        case PhysicalRangeRelation.unrepresentable:
            return copyFailure(
                NonOverlappingCopyError.addressRangeUnrepresentable
            );
    }
}


version (unittest)
{

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.internal.target :
    tryBorrowContiguousTarget;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/*
 * Distinct contiguous source and target ranges are proved non-overlapping and
 * copied through the E3c reference kernel.
 */
unittest
{
    ushort[6] sourceStorage =
        [10, 20, 30, 40, 50, 60];

    ushort[6] targetStorage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            3,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!ushort(
            descriptors[],
            Region2D(
                0,
                0,
                3,
                2
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            targetStorage[],
            3,
            2,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(result.ok);
    assert(targetStorage == sourceStorage);
}


/*
 * Partial physical overlap is detected before the first target write.
 */
unittest
{
    ubyte[5] storage =
        [1, 2, 3, 4, 99];

    const original =
        storage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[1 .. 5],
            4,
            1,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == NonOverlappingCopyError.overlapDetected
    );

    assert(storage == original);
}


/*
 * Exact source/target overlap is likewise rejected.
 */
unittest
{
    uint[4] storage =
        [11, 22, 33, 44];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!uint(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[],
            4,
            1,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == NonOverlappingCopyError.overlapDetected
    );
}


/*
 * Shape mismatch is reported before alias analysis or writes.
 */
unittest
{
    ubyte[6] sourceStorage =
        [1, 2, 3, 4, 5, 6];

    ubyte[4] targetStorage =
        [9, 9, 9, 9];

    const original =
        targetStorage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            3,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                3,
                2
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            targetStorage[],
            2,
            2,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == NonOverlappingCopyError.shapeMismatch
    );

    assert(targetStorage == original);
}


/*
 * A padded Canonical source is valid raster execution, but it is not the flat
 * contiguous capability required by this E4.3 path.
 */
unittest
{
    ubyte[6] sourceStorage =
        [1, 2, 99, 3, 4, 99];

    ubyte[4] targetStorage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            3,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                2,
                2
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            targetStorage[],
            2,
            2,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == NonOverlappingCopyError.unsupportedExecution
    );
}


/*
 * Empty matching shapes succeed without requiring flat-contiguous execution
 * and without forming source or target sample pointers.
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

    auto source =
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

    auto target =
        tryBorrowContiguousTarget(
            targetStorage,
            0,
            7,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            0,
            target
        );

    assert(result.ok);
}


/*
 * Invalid plane index is reported before execution or alias analysis.
 */
unittest
{
    ubyte[4] sourceStorage;
    ubyte[4] targetStorage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            sourceStorage.ptr,
            4,
            1
        )
    ];

    auto source =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            targetStorage[],
            4,
            1,
            success
        );

    assert(success);

    const result =
        tryCopyNonOverlappingContiguous1D(
            source,
            1,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == NonOverlappingCopyError.invalidPlaneIndex
    );
}


/*
 * Half-open adjacent intervals are non-overlapping.
 */
unittest
{
    ubyte[8] storage;

    const relation =
        classifyPhysicalRangeRelation(
            storage.ptr,
            storage.ptr + 4,
            4
        );

    assert(
        relation
        == PhysicalRangeRelation.nonOverlapping
    );
}


/*
 * Address-end overflow is rejected instead of wrapping the interval.
 *
 * Synthetic pointer values are never dereferenced.
 */
unittest
{
    const source =
        cast(const(ubyte)*)(size_t.max - 1);

    auto target =
        cast(ubyte*) 16;

    const relation =
        classifyPhysicalRangeRelation(
            source,
            target,
            4
        );

    assert(
        relation
        == PhysicalRangeRelation.unrepresentable
    );
}

}
