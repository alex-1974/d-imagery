/++
    Trusted construction validation for retained raster layouts.

    This module validates the relationship between:

    - byte-oriented retained resources;
    - element-oriented PlaneDescriptor metadata;
    - resident descriptor-space Region2D geometry;
    - the typed sample T.

    Validation is performed once at a backing-construction boundary so normal
    RasterView access does not repeatedly pay these checks.
+/
module imagery.raster.validation;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;


/++
    Reason why a retained raster layout is not safe to publish as a validated
    RasterView.
+/
package(imagery.raster)
enum BackingValidationError : ubyte
{
    none,

    noPlanes,

    regionExtentOverflow,

    invalidResourceRange,

    nullPlaneBase,

    misalignedPlaneBase,

    coordinateRepresentationOverflow,

    coordinateStrideOverflow,

    offsetOverflow,

    planeOutsideResources
}


/++
    Result of backing-layout validation.

    `planeIndex` identifies the failing plane when the error is plane-specific.
    Otherwise it is size_t.max.
+/
package(imagery.raster)
struct BackingValidationResult
{
    BackingValidationError error =
        BackingValidationError.none;

    size_t planeIndex =
        size_t.max;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == BackingValidationError.none;
    }
}


private
BackingValidationResult failure(
    BackingValidationError error,
    size_t planeIndex = size_t.max
)
@safe
pure
nothrow
@nogc
{
    return BackingValidationResult(
        error,
        planeIndex
    );
}


/++
    Computes:

        coordinate * stride

    in ptrdiff_t without signed overflow.
+/
private
bool checkedCoordinateStride(
    size_t coordinate,
    ptrdiff_t stride,
    out ptrdiff_t result
)
@safe
pure
nothrow
@nogc
{
    result = 0;

    if (
        coordinate == 0
        || stride == 0
    )
    {
        return true;
    }


    if (stride > 0)
    {
        const magnitude =
            cast(size_t) stride;

        const positiveLimit =
            cast(size_t) ptrdiff_t.max;

        if (
            coordinate
            > positiveLimit / magnitude
        )
        {
            return false;
        }

        result =
            cast(ptrdiff_t)(
                coordinate * magnitude
            );

        return true;
    }


    /*
     * Absolute magnitude representable on the negative side:
     *
     *     abs(ptrdiff_t.min)
     *       = ptrdiff_t.max + 1
     */
    const negativeLimit =
        cast(size_t) ptrdiff_t.max + 1;

    const magnitude =
        stride == ptrdiff_t.min
        ? negativeLimit
        : cast(size_t)(-stride);

    if (
        coordinate
        > negativeLimit / magnitude
    )
    {
        return false;
    }

    const product =
        coordinate * magnitude;

    if (product == negativeLimit)
    {
        result =
            ptrdiff_t.min;
    }
    else
    {
        result =
            -cast(ptrdiff_t) product;
    }

    return true;
}


/++
    Adds two ptrdiff_t values without signed overflow.
+/
private
bool checkedAdd(
    ptrdiff_t left,
    ptrdiff_t right,
    out ptrdiff_t result
)
@safe
pure
nothrow
@nogc
{
    result = 0;

    if (
        right > 0
        && left > ptrdiff_t.max - right
    )
    {
        return false;
    }

    if (
        right < 0
        && left < ptrdiff_t.min - right
    )
    {
        return false;
    }

    result =
        left + right;

    return true;
}


/++
    Computes the minimum and maximum element offset contributed by one axis.

    `extent` must be non-zero and the region extent must already have been
    checked for size_t overflow.
+/
private
bool checkedAxisOffsets(
    size_t origin,
    size_t extent,
    ptrdiff_t stride,
    out ptrdiff_t minimum,
    out ptrdiff_t maximum
)
@safe
pure
nothrow
@nogc
{
    minimum = 0;
    maximum = 0;

    assert(extent != 0);

    const last =
        origin + extent - 1;

    ptrdiff_t firstOffset;
    ptrdiff_t lastOffset;

    if (
        !checkedCoordinateStride(
            origin,
            stride,
            firstOffset
        )
    )
    {
        return false;
    }

    if (
        !checkedCoordinateStride(
            last,
            stride,
            lastOffset
        )
    )
    {
        return false;
    }

    if (firstOffset <= lastOffset)
    {
        minimum = firstOffset;
        maximum = lastOffset;
    }
    else
    {
        minimum = lastOffset;
        maximum = firstOffset;
    }

    return true;
}


/++
    Unsigned magnitude of a ptrdiff_t, including ptrdiff_t.min.
+/
private
size_t signedMagnitude(
    ptrdiff_t value
)
@safe
pure
nothrow
@nogc
{
    if (value >= 0)
    {
        return cast(size_t) value;
    }

    if (value == ptrdiff_t.min)
    {
        return cast(size_t) ptrdiff_t.max
            + 1;
    }

    return cast(size_t)(-value);
}


/++
    Converts an element offset magnitude to bytes without size_t overflow.
+/
private
bool checkedOffsetBytes(T)(
    ptrdiff_t elementOffset,
    out size_t byteMagnitude
)
@safe
pure
nothrow
@nogc
{
    byteMagnitude = 0;

    const magnitude =
        signedMagnitude(elementOffset);

    if (
        magnitude
        > size_t.max / T.sizeof
    )
    {
        return false;
    }

    byteMagnitude =
        magnitude * T.sizeof;

    return true;
}


/++
    Validates that a ResourceEntry describes a representable byte range.
+/
private
bool validResourceRange(
    scope const ref ResourceEntry resource
)
@trusted
nothrow
@nogc
{
    if (
        resource.base is null
        && resource.byteLength != 0
    )
    {
        return false;
    }

    const start =
        cast(size_t) resource.base;

    return resource.byteLength
        <= size_t.max - start;
}


/++
    Tests whether one already-valid resource contains every sample reachable
    through one plane descriptor for the supplied region.
+/
private
bool resourceContainsPlaneRegion(T)(
    scope const ref ResourceEntry resource,
    scope const ref PlaneDescriptor descriptor,
    ptrdiff_t minimumOffset,
    ptrdiff_t maximumOffset
)
@trusted
nothrow
@nogc
{
    if (
        resource.base is null
        || resource.byteLength == 0
    )
    {
        return false;
    }

    const resourceStart =
        cast(size_t) resource.base;

    const resourceEnd =
        resourceStart
        + resource.byteLength;

    const planeBase =
        cast(size_t) descriptor.base;


    /*
     * Deliberately require descriptor-space coordinate `(0, 0)` itself to
     * be located inside its retained resource.
     *
     * ROI does not rewrite this pointer; only Region2D changes.
     */
    if (
        planeBase < resourceStart
        || planeBase >= resourceEnd
    )
    {
        return false;
    }


    if (minimumOffset < 0)
    {
        size_t bytesBefore;

        if (
            !checkedOffsetBytes!T(
                minimumOffset,
                bytesBefore
            )
        )
        {
            return false;
        }

        if (
            bytesBefore
            > planeBase - resourceStart
        )
        {
            return false;
        }
    }


    if (maximumOffset >= 0)
    {
        size_t bytesAfter;

        if (
            !checkedOffsetBytes!T(
                maximumOffset,
                bytesAfter
            )
        )
        {
            return false;
        }

        const available =
            resourceEnd - planeBase;

        /*
         * One complete T sample must fit at the maximum reachable address.
         */
        if (T.sizeof > available)
        {
            return false;
        }

        if (
            bytesAfter
            > available - T.sizeof
        )
        {
            return false;
        }
    }

    return true;
}


/++
    Validates a retained raster representation before publication.

    The validator proves the safety properties required by RasterView's
    trusted sample access:

    - at least one logical plane exists;
    - Region2D endpoint arithmetic is representable in size_t;
    - every reachable resident descriptor coordinate is representable in
      ptrdiff_t;
    - retained resource byte ranges are representable;
    - non-empty planes have non-null, T-aligned bases;
    - coordinate/stride products fit ptrdiff_t;
    - combined affine offsets fit ptrdiff_t;
    - every reachable T sample of every plane lies entirely inside at least
      one retained resource.

    Empty regions are representable and require no sample storage. A non-null
    descriptor base in an empty region must still satisfy T alignment.

    Resource ownership/release policy is intentionally separate from address
    reachability validation.
+/
package(imagery.raster)
BackingValidationResult validateRasterBackingLayout(T)(
    const(ResourceEntry)[] resources,
    const(PlaneDescriptor)[] descriptors,
    Region2D region
)
@trusted
nothrow
@nogc
{
    static assert(
        !is(T == void),
        "Raster backing sample type may not be void."
    );


    if (descriptors.length == 0)
    {
        return failure(
            BackingValidationError.noPlanes
        );
    }


    if (!region.hasRepresentableExtent())
    {
        return failure(
            BackingValidationError.regionExtentOverflow
        );
    }


    foreach (resource; resources)
    {
        if (!validResourceRange(resource))
        {
            return failure(
                BackingValidationError.invalidResourceRange
            );
        }
    }


    /*
     * Empty regions contain no reachable sample.
     */
    if (region.empty())
    {
        foreach (
            planeIndex,
            descriptor;
            descriptors
        )
        {
            if (
                descriptor.base !is null
                && (
                    cast(size_t) descriptor.base
                    % T.alignof
                ) != 0
            )
            {
                return failure(
                    BackingValidationError.misalignedPlaneBase,
                    planeIndex
                );
            }
        }

        return BackingValidationResult.init;
    }


    /*
     * RasterView.trySample() converts resident descriptor-space x/y
     * coordinates to ptrdiff_t before applying element strides.
     *
     * Consequently coordinate representation is an independent invariant:
     * zero or negative strides do not permit an otherwise unrepresentable
     * resident coordinate.
     *
     * region is known to be non-empty here and hasRepresentableExtent()
     * already proved the size_t endpoint arithmetic.
     */
    const coordinateLimit =
        cast(size_t) ptrdiff_t.max;

    const lastX =
        region.x + region.width - 1;

    const lastY =
        region.y + region.height - 1;

    if (
        lastX > coordinateLimit
        || lastY > coordinateLimit
    )
    {
        return failure(
            BackingValidationError.coordinateRepresentationOverflow
        );
    }


    foreach (
        planeIndex,
        descriptor;
        descriptors
    )
    {
        if (descriptor.base is null)
        {
            return failure(
                BackingValidationError.nullPlaneBase,
                planeIndex
            );
        }


        if (
            (
                cast(size_t) descriptor.base
                % T.alignof
            ) != 0
        )
        {
            return failure(
                BackingValidationError.misalignedPlaneBase,
                planeIndex
            );
        }


        ptrdiff_t xMinimum;
        ptrdiff_t xMaximum;

        if (
            !checkedAxisOffsets(
                region.x,
                region.width,
                descriptor.sampleStrideElements,
                xMinimum,
                xMaximum
            )
        )
        {
            return failure(
                BackingValidationError.coordinateStrideOverflow,
                planeIndex
            );
        }


        ptrdiff_t yMinimum;
        ptrdiff_t yMaximum;

        if (
            !checkedAxisOffsets(
                region.y,
                region.height,
                descriptor.rowStrideElements,
                yMinimum,
                yMaximum
            )
        )
        {
            return failure(
                BackingValidationError.coordinateStrideOverflow,
                planeIndex
            );
        }


        ptrdiff_t minimumOffset;
        ptrdiff_t maximumOffset;

        if (
            !checkedAdd(
                xMinimum,
                yMinimum,
                minimumOffset
            )
            || !checkedAdd(
                xMaximum,
                yMaximum,
                maximumOffset
            )
        )
        {
            return failure(
                BackingValidationError.offsetOverflow,
                planeIndex
            );
        }


        bool covered = false;

        foreach (resource; resources)
        {
            if (
                resourceContainsPlaneRegion!T(
                    resource,
                    descriptor,
                    minimumOffset,
                    maximumOffset
                )
            )
            {
                covered = true;
                break;
            }
        }


        if (!covered)
        {
            return failure(
                BackingValidationError.planeOutsideResources,
                planeIndex
            );
        }
    }


    return BackingValidationResult.init;
}


version (unittest)
{

unittest
{
    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(result.ok);
}


unittest
{
    /*
     * Three interleaved bands share one retained physical resource.
     */

    ubyte[36] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 0,
            12,
            3
        ),

        PlaneDescriptor(
            samples.ptr + 1,
            12,
            3
        ),

        PlaneDescriptor(
            samples.ptr + 2,
            12,
            3
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(result.ok);
}


unittest
{
    /*
     * Negative row traversal.
     */

    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 8,
            -4,
            1
        )
    ];

    assert(
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        ).ok
    );
}


unittest
{
    /*
     * Negative sample traversal.
     */

    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 3,
            4,
            -1
        )
    ];

    assert(
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        ).ok
    );
}


unittest
{
    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const(PlaneDescriptor)[] descriptors;

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(
        result.error
        == BackingValidationError.noPlanes
    );
}


unittest
{
    ubyte sample;

    const resources =
    [
        ResourceEntry(
            &sample,
            1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            &sample,
            1,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                size_t.max,
                0,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.regionExtentOverflow
    );
}


unittest
{
    /*
     * RasterView is fundamentally 2D.
     *
     * width * height need not be representable until an operation explicitly
     * requests a linearized/flat representation.
     *
     * With zero strides every logical sample aliases one physical byte, so
     * the affine footprint itself remains valid.
     */

    ubyte sample;

    const resources =
    [
        ResourceEntry(
            &sample,
            1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            &sample,
            0,
            0
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                cast(size_t) ptrdiff_t.max,
                3
            )
        );

    assert(result.ok);
}


unittest
{
    const resources =
    [
        ResourceEntry(
            cast(void*)(size_t.max - 3),
            8,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor.init
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D.init
        );

    assert(
        result.error
        == BackingValidationError.invalidResourceRange
    );
}


unittest
{
    ubyte[4] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            null,
            1,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.nullPlaneBase
    );

    assert(result.planeIndex == 0);
}


unittest
{
    ushort[4] words;

    auto misaligned =
        cast(void*)(
            cast(ubyte*) words.ptr
            + 1
        );

    const resources =
    [
        ResourceEntry(
            words.ptr,
            words.sizeof,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            misaligned,
            1,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ushort(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.misalignedPlaneBase
    );
}


unittest
{
    /*
     * Resident descriptor-space coordinates themselves must fit ptrdiff_t
     * because RasterView.trySample() casts them before applying strides.
     *
     * Zero stride deliberately verifies that coordinate representation is
     * checked independently of multiplication.
     */

    ubyte sample;

    const resources =
    [
        ResourceEntry(
            &sample,
            1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            &sample,
            0,
            0
        )
    ];

    const unrepresentableCoordinate =
        cast(size_t) ptrdiff_t.max
        + 1;

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                unrepresentableCoordinate,
                0,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.coordinateRepresentationOverflow
    );
}


unittest
{
    /*
     * Here the resident descriptor coordinate itself is representable, but
     * multiplying it by sampleStrideElements is not.
     */

    ubyte sample;

    const resources =
    [
        ResourceEntry(
            &sample,
            1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            &sample,
            0,
            2
        )
    ];

    const largeCoordinate =
        cast(size_t) ptrdiff_t.max;

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                largeCoordinate,
                0,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.coordinateStrideOverflow
    );
}


unittest
{
    ubyte sample;

    const resources =
    [
        ResourceEntry(
            &sample,
            1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            &sample,
            1,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                cast(size_t) ptrdiff_t.max,
                1,
                1,
                1
            )
        );

    assert(
        result.error
        == BackingValidationError.offsetOverflow
    );
}


unittest
{
    /*
     * Resource is one byte too short for a 4 x 3 ubyte raster.
     */

    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length - 1,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(
        result.error
        == BackingValidationError.planeOutsideResources
    );
}


unittest
{
    /*
     * Empty raster: no sample is reachable, so no physical sample allocation
     * is required.
     */

    const(ResourceEntry)[] resources;

    const descriptors =
    [
        PlaneDescriptor.init
    ];

    const result =
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                10,
                20,
                0,
                0
            )
        );

    assert(result.ok);
}


unittest
{
    /*
     * RasterBacking validation operates in resident descriptor coordinates,
     * not in global LogicalImage coordinates.
     *
     * A tiny 4 x 3 resident block therefore uses a local region even if a
     * higher layer places that block very far inside a logical image.
     */

    ubyte[12] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];


    const residentRegion =
        Region2D(
            0,
            0,
            4,
            3
        );

    const globalPlacement =
        Region2D(
            100_000,
            200_000,
            4,
            3
        );


    assert(
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            residentRegion
        ).ok
    );


    /*
     * Passing the higher-level global placement directly as resident geometry
     * would require a huge physical prefix that this 12-byte resource does not
     * contain.
     *
     * This is deliberately invalid.
     */
    assert(
        !validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            globalPlacement
        ).ok
    );
}


unittest
{
    /*
     * Resident descriptor coordinates are not required to start at zero.
     *
     * This models a retained resource that contains padding, halo, or another
     * physical prefix before the visible resident region.
     */

    ubyte[30] samples;

    const resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null
        )
    ];

    const descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            6,
            1
        )
    ];


    assert(
        validateRasterBackingLayout!ubyte(
            resources,
            descriptors,
            Region2D(
                1,
                1,
                4,
                3
            )
        ).ok
    );
}


} // version (unittest)
