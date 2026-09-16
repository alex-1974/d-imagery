/++
    Transactional retained-raster construction.

    This module is package-internal.

    It converts source-specific physical resource ownership and temporary
    metadata into the stable retained representation used by RasterLease.

    Public source adapters must be built above this layer.
+/
module imagery.raster.construction;

import core.stdc.stdlib :
    free,
    malloc;

import core.stdc.string :
    memcpy;

import std.algorithm.mutation :
    move;

import imagery.raster.backing :
    RasterBacking,
    RasterLease,
    retainRasterBacking;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    validateRasterBackingLayout;


/++
    Construction-stage failure category.

    Validation details remain available separately through
    RasterConstructionResult.validation.
+/
package(imagery.raster)
enum RasterConstructionError : ubyte
{
    none,

    validationFailed,

    resourceMetadataSizeOverflow,

    resourceMetadataAllocationFailed,

    descriptorMetadataSizeOverflow,

    descriptorMetadataAllocationFailed
}


/++
    Result of one retained-raster construction attempt.
+/
package(imagery.raster)
struct RasterConstructionResult
{
    RasterConstructionError error =
        RasterConstructionError.none;

    BackingValidationResult validation;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == RasterConstructionError.none;
    }
}


/++
    Temporary owner used while retained construction is still transactional.

    Ownership contract:

    - while armed, every ResourceEntry belongs to this object;
    - destruction while armed releases every registered resource;
    - once RasterBacking has accepted the copied resource table, `disarm()`
      transfers the release obligation to RasterBacking.

    The input ResourceEntry metadata itself remains caller-owned and is only
    borrowed for the duration of construction.
+/
private
struct PendingResourceOwner
{
private:
    ResourceEntry[] resources_;

    bool armed_;

public:
    @disable this(this);


    ~this()
    @trusted
    nothrow
    @nogc
    {
        if (!armed_)
        {
            return;
        }

        foreach (resource; resources_)
        {
            if (
                resource.base !is null
                && resource.releaseFn !is null
            )
            {
                resource.releaseFn(
                    resource.releaseContext,
                    resource.base,
                    resource.byteLength
                );
            }
        }

        armed_ =
            false;
    }


    void disarm()
    @safe
    pure
    nothrow
    @nogc
    {
        armed_ =
            false;
    }
}


/++
    Failure reason while copying one metadata table.
+/
private
enum MetadataCopyError : ubyte
{
    none,
    sizeOverflow,
    allocationFailed
}


/++
    Allocates one stable metadata table and copies the caller metadata into it.

    The returned slice aliases the returned malloc allocation.

    No physical resource ownership is changed here.
+/
private
MetadataCopyError copyMetadata(T)(
    scope const(T)[] source,
    out T[] copied,
    out void* allocation
)
@trusted
nothrow
@nogc
{
    copied = null;
    allocation = null;


    if (source.length == 0)
    {
        return MetadataCopyError.none;
    }


    if (
        source.length
        > size_t.max / T.sizeof
    )
    {
        return MetadataCopyError.sizeOverflow;
    }


    const byteLength =
        source.length * T.sizeof;

    allocation =
        malloc(byteLength);

    if (allocation is null)
    {
        return MetadataCopyError.allocationFailed;
    }


    memcpy(
        allocation,
        source.ptr,
        byteLength
    );

    copied =
        (cast(T*) allocation)
        [0 .. source.length];

    return MetadataCopyError.none;
}


/++
    Constructs one retained read-only raster transactionally.

    Ownership contract:

    `resources` is an adopting input.

    On entry, responsibility for every release obligation represented by
    `resources` transfers to this function.

    Therefore:

    - on validation failure, this function releases the resources;
    - on metadata-copy failure, this function releases the resources;
    - on success, RasterBacking receives the release obligations;
    - callers must not release adopted resources after this call.

    The ResourceEntry and PlaneDescriptor arrays themselves are not retained.
    Their contents are copied into stable RasterBacking-owned allocations.

    `lease` is reset to RasterLease.init before any work is performed and
    remains empty on ordinary construction failure.

    This function is package-internal until explicit public ownership-transfer
    adapters are designed.
+/
package(imagery.raster)
RasterConstructionResult constructRetainedRaster(T)(
    scope ResourceEntry[] resources,
    scope const(PlaneDescriptor)[] descriptors,
    Region2D region,
    out RasterLease!T lease
)
@trusted
{
    lease =
        RasterLease!T.init;


    /*
     * From this point onward this function owns every physical release
     * obligation supplied by `resources`.
     */
    PendingResourceOwner pending;

    pending.resources_ =
        resources;

    pending.armed_ =
        true;


    const validation =
        validateRasterBackingLayout!T(
            resources,
            descriptors,
            region
        );


    if (!validation.ok)
    {
        return RasterConstructionResult(
            RasterConstructionError.validationFailed,
            validation
        );
    }


    ResourceEntry[] stableResources;

    void* resourceTableAllocation;

    const resourceCopy =
        copyMetadata!ResourceEntry(
            resources,
            stableResources,
            resourceTableAllocation
        );


    final switch (resourceCopy)
    {
        case MetadataCopyError.none:
            break;

        case MetadataCopyError.sizeOverflow:
            return RasterConstructionResult(
                RasterConstructionError.resourceMetadataSizeOverflow,
                BackingValidationResult.init
            );

        case MetadataCopyError.allocationFailed:
            return RasterConstructionResult(
                RasterConstructionError.resourceMetadataAllocationFailed,
                BackingValidationResult.init
            );
    }


    PlaneDescriptor[] stableDescriptors;

    void* descriptorTableAllocation;

    const descriptorCopy =
        copyMetadata!PlaneDescriptor(
            descriptors,
            stableDescriptors,
            descriptorTableAllocation
        );


    final switch (descriptorCopy)
    {
        case MetadataCopyError.none:
            break;

        case MetadataCopyError.sizeOverflow:
            if (resourceTableAllocation !is null)
            {
                free(resourceTableAllocation);
            }

            return RasterConstructionResult(
                RasterConstructionError.descriptorMetadataSizeOverflow,
                BackingValidationResult.init
            );

        case MetadataCopyError.allocationFailed:
            if (resourceTableAllocation !is null)
            {
                free(resourceTableAllocation);
            }

            return RasterConstructionResult(
                RasterConstructionError.descriptorMetadataAllocationFailed,
                BackingValidationResult.init
            );
    }


    /*
     * RasterBacking now owns:
     *
     * - the copied ResourceEntry table;
     * - the copied PlaneDescriptor table;
     * - all physical resource release obligations represented by that table.
     */
    auto backing =
        RasterBacking!T(
            stableResources,
            stableDescriptors,
            resourceTableAllocation,
            descriptorTableAllocation,
            region
        );


    /*
     * Ownership has moved from the temporary transaction into RasterBacking.
     *
     * This must happen only after RasterBacking contains every release
     * obligation.
     */
    pending.disarm();


    /*
     * The local RasterBacking now protects the resources if creation of the
     * SafeRefCounted owner fails through normal stack unwinding.
     *
     * On success retainRasterBacking moves it into the retained owner.
     */
    lease =
        retainRasterBacking!T(
            move(backing)
        );


    return RasterConstructionResult.init;
}


version (unittest)
{

private
void releaseCounted(
    void* context,
    void* base,
    size_t byteLength
)
nothrow
@nogc
{
    auto counter =
        cast(size_t*) context;

    ++*counter;

    free(base);
}


unittest
{
    /*
     * Successful retained construction.
     *
     * The resource must remain alive while the lease exists and must be
     * released exactly once when the final lease disappears.
     */

    size_t releases;

    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t sampleCount = width * height;

    auto pixels =
        cast(ubyte*) malloc(sampleCount);

    assert(pixels !is null);

    foreach (index; 0 .. sampleCount)
    {
        pixels[index] =
            cast(ubyte) index;
    }


    ResourceEntry[1] resources =
    [
        ResourceEntry(
            pixels,
            sampleCount,
            &releases,
            &releaseCounted
        )
    ];


    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            pixels,
            width,
            1
        )
    ];


    {
        RasterLease!ubyte lease;

        const result =
            constructRetainedRaster!ubyte(
                resources[],
                descriptors[],
                Region2D(
                    0,
                    0,
                    width,
                    height
                ),
                lease
            );

        assert(result.ok);

        assert(lease.hasBacking);
        assert(releases == 0);


        auto view =
            lease.view();

        assert(view.width == width);
        assert(view.height == height);
        assert(view.planeCount == 1);


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
     * Validation failure after ownership transfer.
     *
     * The resource is intentionally one byte too short for the requested
     * layout. Construction must reject it and release it exactly once without
     * publishing a RasterLease.
     */

    size_t releases;

    enum size_t width = 4;
    enum size_t height = 3;

    enum size_t requiredSamples =
        width * height;

    enum size_t retainedBytes =
        requiredSamples - 1;


    auto pixels =
        cast(ubyte*) malloc(retainedBytes);

    assert(pixels !is null);


    ResourceEntry[1] resources =
    [
        ResourceEntry(
            pixels,
            retainedBytes,
            &releases,
            &releaseCounted
        )
    ];


    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            pixels,
            width,
            1
        )
    ];


    RasterLease!ubyte lease;

    const result =
        constructRetainedRaster!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                width,
                height
            ),
            lease
        );


    assert(!result.ok);

    assert(
        result.error
        == RasterConstructionError.validationFailed
    );

    assert(!result.validation.ok);

    assert(releases == 1);

    /*
     * Failure must publish no retained backing.
     *
     * Do not call view() here: RasterLease uses SafeRefCounted with
     * RefCountedAutoInitialize.no, so payload access on RasterLease.init is
     * intentionally invalid.
     */
    assert(!lease.hasBacking);
}


} // version (unittest)
