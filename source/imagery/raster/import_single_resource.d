/++
    Transactional join of:

    - one OwnedByteResource;
    - external PlaneByteLayout metadata;
    - one resident Region2D;

    into one retained RasterLease.

    This module is package-internal while the public error/result surface is
    still being designed.

    The key ownership rule is:

    - layout conversion happens before ownership transfer;
    - after ownership transfer, raw retained construction owns the release
      obligation transactionally.
+/
module imagery.raster.import_single_resource;

import core.stdc.stdlib :
    free,
    malloc;

import imagery.raster.backing :
    RasterLease;

import imagery.raster.byte_layout :
    PlaneByteLayout,
    PlaneByteLayoutConversionError,
    convertPlaneByteLayout;

import imagery.raster.construction :
    RasterConstructionError,
    constructRetainedRaster;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.owned_resource :
    OwnedByteResource;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    validateRasterBackingLayout;

import imagery.raster.sample :
    isRasterSampleType;


/++
    Package-internal failure category for the first single-resource retained
    import join.
+/
package(imagery.raster)
enum SingleResourceRasterImportError : ubyte
{
    none,

    emptyResource,

    outputLeaseNotEmpty,

    noPlanes,

    descriptorMetadataSizeOverflow,

    descriptorMetadataAllocationFailed,

    planeLayoutConversionFailed,

    backingValidationFailed,

    retainedConstructionFailed
}


/++
    Package-internal result details.

    `planeIndex` and `layoutError` are meaningful when error is
    planeLayoutConversionFailed.

    `constructionError` is meaningful when error is retainedConstructionFailed.
+/
package(imagery.raster)
struct SingleResourceRasterImportResult
{
    SingleResourceRasterImportError error =
        SingleResourceRasterImportError.none;

    size_t planeIndex =
        size_t.max;

    PlaneByteLayoutConversionError layoutError =
        PlaneByteLayoutConversionError.none;

    BackingValidationResult validation;


    RasterConstructionError constructionError =
        RasterConstructionError.none;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == SingleResourceRasterImportError.none;
    }
}


/++
    Transactionally joins one retained byte resource with plane layouts.

    Ownership phases:

    Phase A: pre-commit

        resource remains armed.

        Layout conversion and temporary descriptor allocation occur here.

        Any failure in this phase leaves resource ownership unchanged.

    Phase B: committed

        resource.relinquishResource() transfers the raw release obligation to
        this function.

        constructRetainedRaster() immediately adopts that obligation.

        From this point failure releases the physical resource exactly once.

    `lease` must be empty on entry.

    The function uses `ref`, not `out`, because a live RasterLease must never be
    silently reset as an output side effect.

    This function remains package-internal while its public-facing error and
    ownership API is reviewed.
+/
package(imagery.raster)
SingleResourceRasterImportResult importSingleOwnedResource(T)(
    ref OwnedByteResource resource,
    scope const(PlaneByteLayout)[] layouts,
    Region2D residentRegion,
    ref RasterLease!T lease
)
@trusted
{
    static assert(
        isRasterSampleType!T,
        "Single-resource raster import requires a valid raster sample type."
    );


    if (!resource.ownsResource)
    {
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.emptyResource
        );
    }


    if (lease.hasBacking)
    {
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.outputLeaseNotEmpty
        );
    }


    if (layouts.length == 0)
    {
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.noPlanes
        );
    }


    if (
        layouts.length
        > size_t.max / PlaneDescriptor.sizeof
    )
    {
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.descriptorMetadataSizeOverflow
        );
    }


    const descriptorBytes =
        layouts.length
        * PlaneDescriptor.sizeof;


    void* descriptorAllocation =
        malloc(descriptorBytes);


    if (descriptorAllocation is null)
    {
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.descriptorMetadataAllocationFailed
        );
    }


    scope(exit)
    {
        free(descriptorAllocation);
    }


    auto descriptors =
        (cast(PlaneDescriptor*) descriptorAllocation)
        [0 .. layouts.length];


    /*
     * PRE-COMMIT PHASE
     *
     * resource still owns the physical release obligation.
     */
    const resourceBase =
        resource.resourceBase;

    const resourceByteLength =
        resource.byteLength;


    foreach (planeIndex, layout; layouts)
    {
        PlaneDescriptor descriptor;


        const conversion =
            convertPlaneByteLayout!T(
                resourceBase,
                resourceByteLength,
                layout,
                descriptor
            );


        if (!conversion.ok)
        {
            return SingleResourceRasterImportResult(
                SingleResourceRasterImportError.planeLayoutConversionFailed,
                planeIndex,
                conversion.error,
                BackingValidationResult.init,
                RasterConstructionError.none
            );
        }


        descriptors[planeIndex] =
            descriptor;
    }


    /*
     * COMPLETE PRE-COMMIT BACKING VALIDATION
     *
     * The validator needs only retained byte-range metadata for physical
     * reachability. Release policy is explicitly outside its responsibility.
     *
     * Therefore construct a temporary validation-only ResourceEntry with no
     * release callback. It carries no ownership obligation.
     *
     * resourceBase originated from the armed OwnedByteResource. Casting away
     * const here does not grant write access or mutate storage; ResourceEntry's
     * historical physical-range representation uses void*.
     */
    ResourceEntry[1] validationResources =
    [
        ResourceEntry(
            cast(void*) resourceBase,
            resourceByteLength,
            null,
            null
        )
    ];


    const validation =
        validateRasterBackingLayout!T(
            validationResources[],
            descriptors[],
            residentRegion
        );


    if (!validation.ok)
    {
        /*
         * Still PRE-COMMIT.
         *
         * The caller retains the original OwnedByteResource unchanged.
         */
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.backingValidationFailed,
            size_t.max,
            PlaneByteLayoutConversionError.none,
            validation,
            RasterConstructionError.none
        );
    }


    /*
     * COMMIT POINT
     *
     * All ownership-independent conversion succeeded.
     *
     * From here onward the caller's OwnedByteResource is deliberately
     * disarmed.
     */
    auto rawResource =
        resource.relinquishResource();


    ResourceEntry[1] resources =
    [
        rawResource
    ];


    const construction =
        constructRetainedRaster!T(
            resources[],
            descriptors[],
            residentRegion,
            lease
        );


    if (!construction.ok)
    {
        /*
         * constructRetainedRaster() adopted the ResourceEntry on entry and
         * therefore already released it on ordinary failure.
         */
        return SingleResourceRasterImportResult(
            SingleResourceRasterImportError.retainedConstructionFailed,
            size_t.max,
            PlaneByteLayoutConversionError.none,
            BackingValidationResult.init,
            construction.error
        );
    }


    return SingleResourceRasterImportResult.init;
}


version (unittest)
{

import core.stdc.stdlib :
    malloc;

import imagery.raster.owned_resource :
    tryAdoptResourceEntryAssumeOwned;


/++
    Count and release one malloc-compatible physical allocation.
+/
private
void releaseCountedImportResource(
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
     * Layout conversion failure is PRE-COMMIT.
     *
     * Ownership must remain in OwnedByteResource.
     */

    size_t releases;

    auto memory =
        cast(ushort*) malloc(8 * ushort.sizeof);

    assert(memory !is null);


    ResourceEntry raw =
        ResourceEntry(
            memory,
            8 * ushort.sizeof,
            &releases,
            &releaseCountedImportResource
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
            importSingleOwnedResource!ushort(
                resource,
                [
                    PlaneByteLayout(
                        0,
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
            == SingleResourceRasterImportError
                .planeLayoutConversionFailed
        );

        assert(
            result.planeIndex
            == 0
        );

        assert(
            result.layoutError
            == PlaneByteLayoutConversionError
                .rowStrideNotDivisibleBySampleSize
        );


        /*
         * No ownership transition occurred.
         */
        assert(resource.ownsResource);
        assert(!lease.hasBacking);
        assert(releases == 0);
    }


    /*
     * Original token still owned it and therefore releases on scope exit.
     */
    assert(releases == 1);
}


unittest
{
    /*
     * Successful one-plane import:
     *
     * OwnedByteResource is disarmed and RasterLease retains the allocation.
     */

    size_t releases;

    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t sampleCount =
        width * height;


    auto memory =
        cast(ubyte*) malloc(sampleCount);

    assert(memory !is null);


    foreach (index; 0 .. sampleCount)
    {
        memory[index] =
            cast(ubyte) index;
    }


    ResourceEntry raw =
        ResourceEntry(
            memory,
            sampleCount,
            &releases,
            &releaseCountedImportResource
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
            importSingleOwnedResource!ubyte(
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

        assert(!resource.ownsResource);
        assert(lease.hasBacking);
        assert(releases == 0);


        auto view =
            lease.view();

        assert(view.planeCount == 1);
        assert(view.width == width);
        assert(view.height == height);


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
        assert(releases == 0);
    }


    assert(releases == 1);
}


unittest
{
    /*
     * Layout conversion can succeed while the complete affine footprint is too
     * large for the physical resource.
     *
     * Full backing validation must detect this PRE-COMMIT.
     *
     * Therefore:
     *
     * - OwnedByteResource remains armed;
     * - no RasterLease is published;
     * - no physical release happens until the token itself is destroyed.
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
            &releaseCountedImportResource
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
            importSingleOwnedResource!ubyte(
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


        assert(!result.ok);

        assert(
            result.error
            == SingleResourceRasterImportError
                .backingValidationFailed
        );

        assert(!result.validation.ok);

        /*
         * Invalid caller geometry never crosses the ownership commit point.
         */
        assert(resource.ownsResource);
        assert(!lease.hasBacking);
        assert(releases == 0);
    }


    /*
     * Token still owned the allocation and releases it normally.
     */
    assert(releases == 1);
}


unittest
{
    /*
     * No planes is PRE-COMMIT and therefore preserves the token.
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
            &releaseCountedImportResource
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


        const PlaneByteLayout[] noLayouts;


        const result =
            importSingleOwnedResource!ubyte(
                resource,
                noLayouts,
                Region2D(
                    0,
                    0,
                    1,
                    1
                ),
                lease
            );


        assert(
            result.error
            == SingleResourceRasterImportError.noPlanes
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
     * A non-empty output lease is rejected PRE-COMMIT.
     *
     * Neither existing lease ownership nor candidate resource ownership may be
     * modified.
     */

    size_t firstReleases;
    size_t secondReleases;


    auto firstMemory =
        cast(ubyte*) malloc(1);

    auto secondMemory =
        cast(ubyte*) malloc(1);

    assert(firstMemory !is null);
    assert(secondMemory !is null);


    ResourceEntry firstRaw =
        ResourceEntry(
            firstMemory,
            1,
            &firstReleases,
            &releaseCountedImportResource
        );

    ResourceEntry secondRaw =
        ResourceEntry(
            secondMemory,
            1,
            &secondReleases,
            &releaseCountedImportResource
        );


    {
        OwnedByteResource firstResource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                firstRaw,
                firstResource
            )
        );


        RasterLease!ubyte lease;


        assert(
            importSingleOwnedResource!ubyte(
                firstResource,
                [
                    PlaneByteLayout(
                        0,
                        1,
                        1
                    )
                ],
                Region2D(
                    0,
                    0,
                    1,
                    1
                ),
                lease
            ).ok
        );


        assert(!firstResource.ownsResource);
        assert(lease.hasBacking);


        OwnedByteResource secondResource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                secondRaw,
                secondResource
            )
        );


        const result =
            importSingleOwnedResource!ubyte(
                secondResource,
                [
                    PlaneByteLayout(
                        0,
                        1,
                        1
                    )
                ],
                Region2D(
                    0,
                    0,
                    1,
                    1
                ),
                lease
            );


        assert(
            result.error
            == SingleResourceRasterImportError
                .outputLeaseNotEmpty
        );


        /*
         * Existing lease remains valid and second candidate remains owned by
         * its token.
         */
        assert(lease.hasBacking);
        assert(secondResource.ownsResource);

        assert(firstReleases == 0);
        assert(secondReleases == 0);
    }


    assert(firstReleases == 1);
    assert(secondReleases == 1);
}


} // version (unittest)
