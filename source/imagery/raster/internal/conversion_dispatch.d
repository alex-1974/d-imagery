/++
    Internal dispatch for exact ubyte-to-float raster conversion.

    E5.3b combines:

    - logical source/target validation;
    - execution capability derived from RasterView;
    - a pairwise physical source/target non-overlap check;
    - the E5.3a scalar conversion reference kernel.

    The physical-range logic deliberately remains local to this operation in
    E5.3b. E5.3c will compare it with checked copy before deciding whether a
    shared lower-level abstraction is justified.

    No public raster-operation API is defined here.
+/
module imagery.raster.internal.conversion_dispatch;

import imagery.raster.internal.execution_layout :
    PlaneExecutionTraits;

import imagery.raster.internal.mir_adapter :
    asMirContiguousFlat;

import imagery.raster.internal.mir_target_adapter :
    asMirTargetContiguousFlat;

import imagery.raster.internal.physical_range :
    PhysicalByteRangeRelation,
    classifyByteAddressRanges;

import imagery.raster.internal.scalar_conversion :
    scalarConvertUbyteToFloatContiguous1D;

import imagery.raster.internal.target :
    RasterTargetPlane;

import imagery.raster.view :
    RasterView;


/++
    Failure category for checked flat ubyte-to-float conversion.
+/
package(imagery.raster)
enum UbyteToFloatConversionError : ubyte
{
    none,

    invalidPlaneIndex,

    shapeMismatch,

    unsupportedExecution,

    overlapDetected,

    addressRangeUnrepresentable
}


/++
    Result of one package-internal ubyte-to-float conversion dispatch.

    `.init` deliberately represents failure rather than success.
+/
package(imagery.raster)
struct UbyteToFloatConversionResult
{
    UbyteToFloatConversionError error =
        UbyteToFloatConversionError.addressRangeUnrepresentable;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == UbyteToFloatConversionError.none;
    }
}


private
UbyteToFloatConversionResult conversionSuccess()
@safe
pure
nothrow
@nogc
{
    UbyteToFloatConversionResult result;

    result.error =
        UbyteToFloatConversionError.none;

    return result;
}


private
UbyteToFloatConversionResult conversionFailure(
    UbyteToFloatConversionError error
)
@safe
pure
nothrow
@nogc
{
    UbyteToFloatConversionResult result;

    result.error =
        error;

    return result;
}


/++
    Classifies the physical ranges used by one non-empty ubyte-to-float
    conversion.

    Unlike same-type copy, the source and target byte lengths differ:

        sourceByteLength = elementCount * ubyte.sizeof
        targetByteLength = elementCount * float.sizeof

    The function converts pointers to the project's flat integer-address
    representation and validates all byte-length and end-address arithmetic
    before comparing the half-open ranges.

    No source or target memory is dereferenced or modified here.
+/
private
PhysicalByteRangeRelation classifyConversionPhysicalRanges(
    scope const(ubyte)* sourceBase,
    scope float* targetBase,
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
        > size_t.max / ubyte.sizeof
    )
    {
        return
            PhysicalByteRangeRelation.unrepresentable;
    }

    if (
        elementCount
        > size_t.max / float.sizeof
    )
    {
        return
            PhysicalByteRangeRelation.unrepresentable;
    }

    const sourceByteLength =
        elementCount * ubyte.sizeof;

    const targetByteLength =
        elementCount * float.sizeof;

    const sourceStart =
        cast(size_t) sourceBase;

    const targetStart =
        cast(size_t) targetBase;

    return classifyByteAddressRanges(
        sourceStart,
        sourceByteLength,
        targetStart,
        targetByteLength
    );
}


/++
    Converts one ubyte source plane into a contiguous float target.

    Preconditions are established internally in this order:

    - plane index must be valid;
    - source and target logical width/height must match;
    - matching empty shapes succeed without forming physical ranges;
    - source must provide flat Contiguous 1D execution;
    - source and target physical byte intervals must be representable;
    - those intervals must not overlap.

    Failure occurs before the first target write.

    On successful non-empty dispatch the E5.3a scalar reference kernel performs
    the exact per-sample conversion:

        target[i] = cast(float) source[i]
+/
package(imagery.raster)
UbyteToFloatConversionResult tryConvertUbyteToFloatContiguous1D(
    scope RasterView!ubyte source,
    size_t planeIndex,
    scope RasterTargetPlane!float target
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
        return conversionFailure(
            UbyteToFloatConversionError.invalidPlaneIndex
        );
    }

    if (
        source.width != target.width
        || source.height != target.height
    )
    {
        return conversionFailure(
            UbyteToFloatConversionError.shapeMismatch
        );
    }

    /*
     * Matching empty shapes contain no samples and therefore no physical
     * source/target sample intervals requiring an alias proof.
     */
    if (source.empty)
        return conversionSuccess();

    if (!traits.linearContiguous1D)
    {
        return conversionFailure(
            UbyteToFloatConversionError.unsupportedExecution
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
        classifyConversionPhysicalRanges(
            sourceBase,
            targetBase,
            traits.flatElementCount
        )
    )
    {
        case PhysicalByteRangeRelation.overlapping:
            return conversionFailure(
                UbyteToFloatConversionError.overlapDetected
            );

        case PhysicalByteRangeRelation.unrepresentable:
            return conversionFailure(
                UbyteToFloatConversionError.addressRangeUnrepresentable
            );

        case PhysicalByteRangeRelation.nonOverlapping:
        {
            const converted =
                scalarConvertUbyteToFloatContiguous1D(
                    asMirContiguousFlat(
                        source,
                        planeIndex
                    ),
                    asMirTargetContiguousFlat(
                        target
                    )
                );

            /*
             * Shape equality and the source flat element count were already
             * established above.
             */
            assert(converted);

            return conversionSuccess();
        }
    }
}


version (unittest)
{

import core.stdc.stdlib :
    malloc;

import imagery.raster.backing :
    RasterLease;

import imagery.raster.byte_layout :
    PlaneByteLayout;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.import_owned :
    tryImportOwnedRaster;

import imagery.raster.internal.target :
    tryBorrowContiguousTarget;

import imagery.raster.owned_resource :
    OwnedByteResource,
    tryAdoptMallocResource;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/*
 * Distinct flat source and target storage converts successfully.
 */
unittest
{
    ubyte[6] sourceStorage =
        [0, 1, 127, 128, 254, 255];

    float[6] targetStorage =
        [-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f];

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
            3,
            2,
            success
        );

    assert(success);

    const result =
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(result.ok);

    const float[6] expected =
        [0.0f, 1.0f, 127.0f, 128.0f, 254.0f, 255.0f];

    assert(targetStorage == expected);
}


/*
 * Logical shape mismatch fails before the first target write even when both
 * operands contain the same number of elements.
 */
unittest
{
    ubyte[4] sourceStorage =
        [1, 2, 3, 4];

    float[4] targetStorage =
        [91.0f, 92.0f, 93.0f, 94.0f];

    const float[4] expected =
        targetStorage;

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
            2,
            2,
            success
        );

    assert(success);

    const result =
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == UbyteToFloatConversionError.shapeMismatch
    );

    assert(targetStorage == expected);
}


/*
 * A padded Canonical source is not flat Contiguous 1D and is rejected before
 * the target is modified.
 */
unittest
{
    ubyte[8] sourceStorage =
        [1, 2, 3, 99, 4, 5, 6, 99];

    float[6] targetStorage =
        [51.0f, 52.0f, 53.0f, 54.0f, 55.0f, 56.0f];

    const float[6] expected =
        targetStorage;

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
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == UbyteToFloatConversionError.unsupportedExecution
    );

    assert(targetStorage == expected);
}


/*
 * Matching empty shapes succeed before execution-pointer formation or
 * non-empty capability requirements.
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

    float[] targetStorage;

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
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(result.ok);
}


/*
 * An invalid source plane index is reported distinctly.
 */
unittest
{
    ubyte[4] sourceStorage =
        [1, 2, 3, 4];

    float[4] targetStorage;

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
        tryConvertUbyteToFloatContiguous1D(
            source,
            1,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == UbyteToFloatConversionError.invalidPlaneIndex
    );
}


/*
 * Source and target may occupy the same underlying storage. Such overlap is
 * detected before the conversion kernel writes the target.
 */
unittest
{
    union SharedStorage
    {
        ubyte[16] bytes;
        float[4] floats;
    }

    SharedStorage storage;

    storage.floats =
        [91.0f, 92.0f, 93.0f, 94.0f];

    const float[4] expected =
        storage.floats;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.bytes.ptr,
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
            storage.floats[],
            4,
            1,
            success
        );

    assert(success);

    const result =
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(!result.ok);

    assert(
        result.error
        == UbyteToFloatConversionError.overlapDetected
    );

    assert(storage.floats == expected);
}


/*
 * The target byte extent can become unrepresentable even when the source byte
 * extent still fits.
 *
 * Synthetic pointers are never dereferenced.
 */
unittest
{
    const elementCount =
        size_t.max / float.sizeof + 1;

    const relation =
        classifyConversionPhysicalRanges(
            cast(const(ubyte)*) 16,
            cast(float*) 32,
            elementCount
        );

    assert(
        relation
        == PhysicalByteRangeRelation.unrepresentable
    );
}


/*
 * Address-end overflow is also reported without dereferencing either pointer.
 */
unittest
{
    const relation =
        classifyConversionPhysicalRanges(
            cast(const(ubyte)*)
                (size_t.max - 1),
            cast(float*) 16,
            4
        );

    assert(
        relation
        == PhysicalByteRangeRelation.unrepresentable
    );
}


/*
 * Half-open ranges that meet exactly at one boundary do not overlap.
 *
 * For four samples the source occupies [16,20) and the float target starts at
 * 20, occupying [20,36).
 */
unittest
{
    const relation =
        classifyConversionPhysicalRanges(
            cast(const(ubyte)*) 16,
            cast(float*) 20,
            4
        );

    assert(
        relation
        == PhysicalByteRangeRelation.nonOverlapping
    );
}


/*
 * E5.4e.3 retained consumer integration.
 *
 * The float destination reaches the unchanged conversion dispatcher through:
 *
 *     OwnedByteResource
 *         -> RasterLease!float
 *         -> WritableRasterView!float
 *         -> RasterTargetPlane!float
 *         -> tryConvertUbyteToFloatContiguous1D
 *
 * Conversion semantics and invocation-local physical-range checking remain in
 * the existing dispatcher.
 */
unittest
{
    enum size_t width = 3;
    enum size_t height = 2;
    enum size_t elementCount =
        width * height;

    enum size_t sourceByteLength =
        elementCount * ubyte.sizeof;

    enum size_t targetByteLength =
        elementCount * float.sizeof;


    auto sourceMemory =
        cast(ubyte*) malloc(
            sourceByteLength
        );

    auto targetMemory =
        cast(float*) malloc(
            targetByteLength
        );

    assert(sourceMemory !is null);
    assert(targetMemory !is null);


    const ubyte[elementCount] sourceValues =
        [0, 1, 127, 128, 254, 255];


    foreach (index; 0 .. elementCount)
    {
        sourceMemory[index] =
            sourceValues[index];

        targetMemory[index] =
            -1.0f;
    }


    OwnedByteResource sourceResource;
    OwnedByteResource targetResource;

    assert(
        tryAdoptMallocResource(
            cast(void*) sourceMemory,
            sourceByteLength,
            sourceResource
        )
    );

    assert(
        tryAdoptMallocResource(
            cast(void*) targetMemory,
            targetByteLength,
            targetResource
        )
    );


    RasterLease!ubyte sourceLease;
    RasterLease!float targetLease;


    const PlaneByteLayout[1] sourceLayout =
    [
        PlaneByteLayout(
            0,
            width,
            1
        )
    ];

    const PlaneByteLayout[1] targetLayout =
    [
        PlaneByteLayout(
            0,
            width * float.sizeof,
            float.sizeof
        )
    ];


    const sourceImport =
        tryImportOwnedRaster!ubyte(
            sourceResource,
            sourceLayout[],
            Region2D(
                0,
                0,
                width,
                height
            ),
            sourceLease
        );

    const targetImport =
        tryImportOwnedRaster!float(
            targetResource,
            targetLayout[],
            Region2D(
                0,
                0,
                width,
                height
            ),
            targetLease
        );

    assert(sourceImport.ok);
    assert(targetImport.ok);

    assert(!sourceResource.ownsResource);
    assert(!targetResource.ownsResource);


    auto source =
        sourceLease.view();


    bool writableSuccess;

    auto writable =
        targetLease.tryWritableView(
            writableSuccess
        );

    assert(writableSuccess);


    bool targetSuccess;

    auto target =
        tryBorrowContiguousTarget(
            writable,
            0,
            targetSuccess
        );

    assert(targetSuccess);


    const result =
        tryConvertUbyteToFloatContiguous1D(
            source,
            0,
            target
        );

    assert(result.ok);

    assert(
        result.error
        == UbyteToFloatConversionError.none
    );


    auto readableTarget =
        targetLease.view();

    foreach (index; 0 .. elementCount)
    {
        float value;

        assert(
            readableTarget.trySample(
                0,
                index % width,
                index / width,
                value
            )
        );

        assert(
            value
            == cast(float) sourceValues[index]
        );
    }
}

}
