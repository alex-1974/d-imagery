/++
    Public retained import API for one owned physical raster resource.

    Raw external pointer ownership is established separately through an
    explicit @system adoption boundary such as tryAdoptMallocResource().

    Once an OwnedByteResource exists, this module provides the @safe transition
    from:

        OwnedByteResource + PlaneByteLayout[] + Region2D

    to:

        RasterLease!T

    The raw pointer and release machinery remain behind package-internal
    trusted/system boundaries.
+/
module imagery.raster.import_owned;

import imagery.raster.backing :
    RasterLease;

import imagery.raster.byte_layout :
    PlaneByteLayout;

import imagery.raster.construction :
    RasterConstructionError;

import imagery.raster.import_single_resource :
    SingleResourceRasterImportError,
    SingleResourceRasterImportResult,
    importSingleOwnedResource;

import imagery.raster.owned_resource :
    OwnedByteResource;

import imagery.raster.region :
    Region2D;

import imagery.raster.sample :
    isRasterSampleType;


/++
    Stable public error categories for retained owned-raster import.

    These deliberately abstract package-internal conversion, validation, and
    backing-construction details.
+/
enum OwnedRasterImportError : ubyte
{
    none,

    emptyResource,

    outputLeaseNotEmpty,

    noPlanes,

    temporaryMetadataAllocationFailed,

    invalidPlaneLayout,

    invalidBackingLayout,

    backingAllocationFailed,

    internalConstructionFailure
}


/++
    What happened to the physical release obligation during an import attempt.

    This is explicit rather than derived solely from OwnedRasterImportError,
    because one public error category can abstract internal failures occurring
    on different sides of the ownership commit point.
+/
enum OwnedRasterResourceDisposition : ubyte
{
    unchanged,

    transferredToLease,

    releasedAfterCommit
}


/++
    Stable public result of one retained owned-raster import attempt.

    Arbitrary error/disposition combinations cannot be constructed through the
    public API.

    The default `.init` state is deliberately a failure state, not success.
+/
struct OwnedRasterImportResult
{
private:
    OwnedRasterImportError error_ =
        OwnedRasterImportError.internalConstructionFailure;

    size_t planeIndex_ =
        size_t.max;

    OwnedRasterResourceDisposition resourceDisposition_ =
        OwnedRasterResourceDisposition.unchanged;


    this(
        OwnedRasterImportError error,
        size_t planeIndex,
        OwnedRasterResourceDisposition resourceDisposition
    )
    @safe
    pure
    nothrow
    @nogc
    {
        error_ =
            error;

        planeIndex_ =
            planeIndex;

        resourceDisposition_ =
            resourceDisposition;
    }


public:
    /++
        Public error category.
    +/
    @property
    OwnedRasterImportError error() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error_;
    }


    /++
        Zero-based failing logical plane for invalidPlaneLayout.

        Returns size_t.max when the result is not associated with one specific
        plane.
    +/
    @property
    size_t planeIndex() const
    @safe
    pure
    nothrow
    @nogc
    {
        return planeIndex_;
    }


    /++
        Whether the import completed successfully.
    +/
    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error_
            == OwnedRasterImportError.none;
    }


    /++
        Disposition of the physical release obligation.
    +/
    @property
    OwnedRasterResourceDisposition resourceDisposition() const
    @safe
    pure
    nothrow
    @nogc
    {
        return resourceDisposition_;
    }
}


/++
    Constructs one internally consistent public result.

    This helper remains module-private so callers cannot fabricate contradictory
    ownership states.
+/
private
OwnedRasterImportResult makePublicImportResult(
    OwnedRasterImportError error,
    OwnedRasterResourceDisposition disposition,
    size_t planeIndex = size_t.max
)
@safe
pure
nothrow
@nogc
{
    return OwnedRasterImportResult(
        error,
        planeIndex,
        disposition
    );
}


/++
    Maps package-internal import details onto the stable public API.

    The error category and ownership disposition are mapped together.

    This is important because internalConstructionFailure may describe either:

    - a PRE-COMMIT internal failure, where ownership remains unchanged; or
    - a POST-COMMIT retained-construction failure, where the resource has
      already been released.
+/
private
OwnedRasterImportResult mapInternalImportResult(
    SingleResourceRasterImportResult internal
)
@safe
pure
nothrow
@nogc
{
    final switch (internal.error)
    {
        case SingleResourceRasterImportError.none:
            return makePublicImportResult(
                OwnedRasterImportError.none,
                OwnedRasterResourceDisposition.transferredToLease
            );


        case SingleResourceRasterImportError.emptyResource:
            return makePublicImportResult(
                OwnedRasterImportError.emptyResource,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError.outputLeaseNotEmpty:
            return makePublicImportResult(
                OwnedRasterImportError.outputLeaseNotEmpty,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError.noPlanes:
            return makePublicImportResult(
                OwnedRasterImportError.noPlanes,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError.descriptorMetadataSizeOverflow:
            return makePublicImportResult(
                OwnedRasterImportError.internalConstructionFailure,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError
            .descriptorMetadataAllocationFailed:
            return makePublicImportResult(
                OwnedRasterImportError.temporaryMetadataAllocationFailed,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError.planeLayoutConversionFailed:
            return makePublicImportResult(
                OwnedRasterImportError.invalidPlaneLayout,
                OwnedRasterResourceDisposition.unchanged,
                internal.planeIndex
            );


        case SingleResourceRasterImportError.backingValidationFailed:
            return makePublicImportResult(
                OwnedRasterImportError.invalidBackingLayout,
                OwnedRasterResourceDisposition.unchanged
            );


        case SingleResourceRasterImportError.retainedConstructionFailed:
            final switch (internal.constructionError)
            {
                case RasterConstructionError.resourceMetadataAllocationFailed:
                case RasterConstructionError
                    .descriptorMetadataAllocationFailed:
                    return makePublicImportResult(
                        OwnedRasterImportError.backingAllocationFailed,
                        OwnedRasterResourceDisposition.releasedAfterCommit
                    );


                case RasterConstructionError.none:
                case RasterConstructionError.validationFailed:
                case RasterConstructionError.resourceMetadataSizeOverflow:
                case RasterConstructionError.descriptorMetadataSizeOverflow:
                    return makePublicImportResult(
                        OwnedRasterImportError.internalConstructionFailure,
                        OwnedRasterResourceDisposition.releasedAfterCommit
                    );
            }
    }
}


/++
    Imports one retained raster backed by one OwnedByteResource.

    The function itself is @safe.

    The unsafe ownership claim has already occurred when the external physical
    resource was wrapped in OwnedByteResource.

    Ownership semantics:

    PRE-COMMIT failure:
        resource remains armed;
        lease remains unchanged.

    success:
        resource is disarmed;
        lease retains the physical resource.

    POST-COMMIT failure:
        resource is disarmed;
        retained construction has released the physical resource exactly once;
        no new lease is published.

    `lease` must be empty on entry.

    Multiple PlaneByteLayout entries may describe multiple logical planes
    within the same physical allocation.
+/
OwnedRasterImportResult tryImportOwnedRaster(T)(
    ref OwnedByteResource resource,
    scope const(PlaneByteLayout)[] planes,
    Region2D residentRegion,
    ref RasterLease!T lease
)
@safe
{
    static assert(
        isRasterSampleType!T,
        "Owned raster import requires a valid raster sample type."
    );


    const internal =
        importSingleOwnedResource!T(
            resource,
            planes,
            residentRegion,
            lease
        );


    return mapInternalImportResult(
        internal
    );
}


version (unittest)
{

import core.stdc.stdlib :
    free,
    malloc;

import imagery.raster.owned_resource :
    tryAdoptResourceEntryAssumeOwned;

import imagery.raster.resource :
    ResourceEntry;


/++
    Count and release one malloc-compatible test allocation.
+/
private
void releaseCountedPublicImportResource(
    void* context,
    void* base,
    size_t byteLength
)
nothrow
@nogc
{
    auto releases =
        cast(size_t*) context;

    ++*releases;

    free(base);
}


unittest
{
    /*
     * `.init` must never pretend that an import succeeded.
     */

    OwnedRasterImportResult result;

    assert(!result.ok);

    assert(
        result.error
        == OwnedRasterImportError.internalConstructionFailure
    );

    assert(
        result.planeIndex
        == size_t.max
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.unchanged
    );
}


unittest
{
    /*
     * Pure mapping audit: success.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.none;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(result.ok);

    assert(
        result.error
        == OwnedRasterImportError.none
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.transferredToLease
    );
}


unittest
{
    /*
     * Pure mapping audit: PRE-COMMIT internal size failure.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.descriptorMetadataSizeOverflow;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.internalConstructionFailure
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.unchanged
    );
}


unittest
{
    /*
     * Pure mapping audit: temporary descriptor allocation failure.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError
            .descriptorMetadataAllocationFailed;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.temporaryMetadataAllocationFailed
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.unchanged
    );
}


unittest
{
    /*
     * Pure mapping audit: failing logical plane index is preserved.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.planeLayoutConversionFailed;

    internal.planeIndex =
        7;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.invalidPlaneLayout
    );

    assert(result.planeIndex == 7);

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.unchanged
    );
}


unittest
{
    /*
     * Pure mapping audit: backing validation is PRE-COMMIT.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.backingValidationFailed;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.invalidBackingLayout
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.unchanged
    );
}


unittest
{
    /*
     * Pure mapping audit: retained metadata allocation failure occurs after
     * ownership commit.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.retainedConstructionFailed;

    internal.constructionError =
        RasterConstructionError.resourceMetadataAllocationFailed;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.backingAllocationFailed
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.releasedAfterCommit
    );
}


unittest
{
    /*
     * Pure mapping audit: unexpected retained validation failure is also
     * POST-COMMIT.
     */

    SingleResourceRasterImportResult internal;

    internal.error =
        SingleResourceRasterImportError.retainedConstructionFailed;

    internal.constructionError =
        RasterConstructionError.validationFailed;


    const result =
        mapInternalImportResult(
            internal
        );


    assert(
        result.error
        == OwnedRasterImportError.internalConstructionFailure
    );

    assert(
        result.resourceDisposition
        == OwnedRasterResourceDisposition.releasedAfterCommit
    );
}


unittest
{
    /*
     * Public success path.
     */

    size_t releases;

    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t byteLength =
        width * height;


    auto memory =
        cast(ubyte*) malloc(byteLength);

    assert(memory !is null);


    foreach (index; 0 .. byteLength)
    {
        memory[index] =
            cast(ubyte) index;
    }


    ResourceEntry raw =
        ResourceEntry(
            memory,
            byteLength,
            &releases,
            &releaseCountedPublicImportResource
        );


    {
        OwnedByteResource resource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                raw,
                resource
            )
        );


        RasterLease!ubyte lease;


        const result =
            tryImportOwnedRaster!ubyte(
                resource,
                [
                    PlaneByteLayout(
                        0,
                        width,
                        1
                    )
                ],
                Region2D(
                    0,
                    0,
                    width,
                    height
                ),
                lease
            );


        assert(result.ok);

        assert(
            result.error
            == OwnedRasterImportError.none
        );

        assert(
            result.resourceDisposition
            == OwnedRasterResourceDisposition.transferredToLease
        );

        assert(result.planeIndex == size_t.max);

        assert(!resource.ownsResource);
        assert(lease.hasBacking);

        assert(releases == 0);


        auto view =
            lease.view();

        ubyte value;

        assert(
            view.trySample(
                0,
                3,
                2,
                value
            )
        );

        assert(value == 11);
    }


    assert(releases == 1);
}


unittest
{
    /*
     * Public invalid plane-layout failure preserves ownership and reports the
     * logical failing plane.
     */

    size_t releases;


    auto memory =
        cast(ushort*) malloc(32);

    assert(memory !is null);


    ResourceEntry raw =
        ResourceEntry(
            memory,
            32,
            &releases,
            &releaseCountedPublicImportResource
        );


    {
        OwnedByteResource resource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                raw,
                resource
            )
        );


        RasterLease!ushort lease;


        const result =
            tryImportOwnedRaster!ushort(
                resource,
                [
                    PlaneByteLayout(
                        0,
                        8,
                        2
                    ),
                    PlaneByteLayout(
                        2,
                        8,
                        2
                    ),
                    PlaneByteLayout(
                        4,
                        3,
                        2
                    )
                ],
                Region2D(
                    0,
                    0,
                    4,
                    2
                ),
                lease
            );


        assert(!result.ok);

        assert(
            result.error
            == OwnedRasterImportError.invalidPlaneLayout
        );

        assert(result.planeIndex == 2);

        assert(
            result.resourceDisposition
            == OwnedRasterResourceDisposition.unchanged
        );

        assert(resource.ownsResource);
        assert(!lease.hasBacking);

        assert(releases == 0);
    }


    assert(releases == 1);
}


unittest
{
    /*
     * Public affine backing failure also remains PRE-COMMIT.
     */

    size_t releases;


    auto memory =
        cast(ubyte*) malloc(4);

    assert(memory !is null);


    ResourceEntry raw =
        ResourceEntry(
            memory,
            4,
            &releases,
            &releaseCountedPublicImportResource
        );


    {
        OwnedByteResource resource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                raw,
                resource
            )
        );


        RasterLease!ubyte lease;


        const result =
            tryImportOwnedRaster!ubyte(
                resource,
                [
                    PlaneByteLayout(
                        0,
                        4,
                        1
                    )
                ],
                Region2D(
                    0,
                    0,
                    4,
                    2
                ),
                lease
            );


        assert(
            result.error
            == OwnedRasterImportError.invalidBackingLayout
        );

        assert(
            result.resourceDisposition
            == OwnedRasterResourceDisposition.unchanged
        );

        assert(resource.ownsResource);
        assert(!lease.hasBacking);

        assert(releases == 0);
    }


    assert(releases == 1);
}


} // version (unittest)
