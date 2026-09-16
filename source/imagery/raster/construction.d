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


alias MetadataAllocateFn =
    void* function(size_t byteLength)
    nothrow
    @nogc;

alias MetadataFreeFn =
    void function(void* allocation)
    nothrow
    @nogc;


private
void* allocateMetadata(
    size_t byteLength
)
nothrow
@nogc
{
    return malloc(byteLength);
}


private
void freeMetadata(
    void* allocation
)
nothrow
@nogc
{
    free(allocation);
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
    out void* allocation,
    MetadataAllocateFn allocate
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
        allocate(byteLength);

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
private
RasterConstructionResult constructRetainedRasterWithMetadataOps(T)(
    scope ResourceEntry[] resources,
    scope const(PlaneDescriptor)[] descriptors,
    Region2D region,
    out RasterLease!T lease,
    MetadataAllocateFn allocateMetadataFn,
    MetadataFreeFn freeMetadataFn
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
            resourceTableAllocation,
            allocateMetadataFn
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
            descriptorTableAllocation,
            allocateMetadataFn
        );


    final switch (descriptorCopy)
    {
        case MetadataCopyError.none:
            break;

        case MetadataCopyError.sizeOverflow:
            if (resourceTableAllocation !is null)
            {
                freeMetadataFn(resourceTableAllocation);
            }

            return RasterConstructionResult(
                RasterConstructionError.descriptorMetadataSizeOverflow,
                BackingValidationResult.init
            );

        case MetadataCopyError.allocationFailed:
            if (resourceTableAllocation !is null)
            {
                freeMetadataFn(resourceTableAllocation);
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


/++
    Production entry point for transactional retained construction.

    Metadata tables use malloc/free-compatible storage.

    Recoverable metadata-allocation failures are returned through
    RasterConstructionResult.

    Allocation failure inside Phobos SafeRefCounted is not translated into a
    RasterConstructionResult; that is an Error-level runtime condition.
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
    return constructRetainedRasterWithMetadataOps!T(
        resources,
        descriptors,
        region,
        lease,
        &allocateMetadata,
        &freeMetadata
    );
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


private size_t controlledAllocationCalls;
private size_t controlledFailureCall;
private size_t controlledFreeCalls;


private
void resetControlledMetadataAllocator(
    size_t failOnCall
)
nothrow
@nogc
{
    controlledAllocationCalls = 0;
    controlledFailureCall = failOnCall;
    controlledFreeCalls = 0;
}


private
void* controlledMetadataAllocate(
    size_t byteLength
)
nothrow
@nogc
{
    ++controlledAllocationCalls;

    if (
        controlledFailureCall != 0
        && controlledAllocationCalls
            == controlledFailureCall
    )
    {
        return null;
    }

    return malloc(byteLength);
}


private
void controlledMetadataFree(
    void* allocation
)
nothrow
@nogc
{
    if (allocation !is null)
    {
        ++controlledFreeCalls;
        free(allocation);
    }
}


unittest
{
    /*
     * First metadata allocation fails.
     *
     * Physical ownership has already transferred into construction, so the
     * resource must still be released exactly once.
     *
     * No metadata allocation exists to free.
     */

    size_t releases;

    auto pixels =
        cast(ubyte*) malloc(1);

    assert(pixels !is null);


    ResourceEntry[1] resources =
    [
        ResourceEntry(
            pixels,
            1,
            &releases,
            &releaseCounted
        )
    ];


    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            pixels,
            1,
            1
        )
    ];


    resetControlledMetadataAllocator(1);

    RasterLease!ubyte lease;

    const result =
        constructRetainedRasterWithMetadataOps!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                1,
                1
            ),
            lease,
            &controlledMetadataAllocate,
            &controlledMetadataFree
        );


    assert(!result.ok);

    assert(
        result.error
        == RasterConstructionError.resourceMetadataAllocationFailed
    );

    assert(controlledAllocationCalls == 1);
    assert(controlledFreeCalls == 0);

    assert(releases == 1);
    assert(!lease.hasBacking);
}


unittest
{
    /*
     * Resource metadata allocation succeeds, descriptor metadata allocation
     * fails.
     *
     * Construction must:
     *
     * - free the already allocated ResourceEntry table exactly once;
     * - release the adopted physical resource exactly once;
     * - publish no RasterLease.
     */

    size_t releases;

    auto pixels =
        cast(ubyte*) malloc(1);

    assert(pixels !is null);


    ResourceEntry[1] resources =
    [
        ResourceEntry(
            pixels,
            1,
            &releases,
            &releaseCounted
        )
    ];


    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            pixels,
            1,
            1
        )
    ];


    resetControlledMetadataAllocator(2);

    RasterLease!ubyte lease;

    const result =
        constructRetainedRasterWithMetadataOps!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                1,
                1
            ),
            lease,
            &controlledMetadataAllocate,
            &controlledMetadataFree
        );


    assert(!result.ok);

    assert(
        result.error
        == RasterConstructionError.descriptorMetadataAllocationFailed
    );

    assert(controlledAllocationCalls == 2);

    /*
     * Only the first metadata allocation existed and therefore exactly one
     * metadata free is required here.
     */
    assert(controlledFreeCalls == 1);

    assert(releases == 1);
    assert(!lease.hasBacking);
}


private size_t ephemeralMetadataReleases;


/++
    Constructs a retained raster from metadata whose storage is local to this
    function.

    Before returning the lease, the caller-side ResourceEntry and
    PlaneDescriptor tables are deliberately overwritten.

    A valid returned RasterLease therefore proves both:

    - construction copied the metadata into stable backing-owned tables;
    - RasterLease does not retain a lifetime dependency on these local arrays.
+/
private
RasterLease!ubyte makeLeaseFromEphemeralMetadata()
{
    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t sampleCount =
        width * height;


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
            &ephemeralMetadataReleases,
            &releaseCounted
        )
    ];


    PlaneDescriptor[1] descriptors =
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


    assert(result.ok);
    assert(lease.hasBacking);
    assert(ephemeralMetadataReleases == 0);


    /*
     * Poison the complete caller-side metadata after construction.
     *
     * Any retained alias to these arrays would now break either sample access
     * or final resource release.
     */
    resources[0] =
        ResourceEntry.init;

    descriptors[0] =
        PlaneDescriptor.init;


    return lease;
}


unittest
{
    /*
     * The helper's metadata arrays disappear completely before this test uses
     * the returned lease.
     */

    ephemeralMetadataReleases = 0;


    {
        auto lease =
            makeLeaseFromEphemeralMetadata();

        assert(lease.hasBacking);
        assert(ephemeralMetadataReleases == 0);


        auto view =
            lease.view();

        assert(view.planeCount == 1);
        assert(view.width == 4);
        assert(view.height == 3);


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


        /*
         * Exercise additional addresses so the proof is not accidentally
         * limited to one sample.
         */
        assert(
            view.trySample(
                0,
                0,
                0,
                value
            )
        );

        assert(value == 0);


        assert(
            view.trySample(
                0,
                1,
                1,
                value
            )
        );

        assert(value == 5);


        assert(ephemeralMetadataReleases == 0);
    }


    /*
     * The copied ResourceEntry still carries the original release operation
     * even though the caller's ResourceEntry was overwritten and its scope has
     * ended.
     */
    assert(ephemeralMetadataReleases == 1);
}


unittest
{
    /*
     * Planar topology:
     *
     * three logical planes backed by three independent physical resources.
     *
     * Every resource must:
     *
     * - remain retained while RasterLease exists;
     * - feed the correct logical band;
     * - be released exactly once when the final lease disappears.
     */

    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t sampleCount =
        width * height;


    size_t[3] releases;


    auto plane0 =
        cast(ubyte*) malloc(sampleCount);

    auto plane1 =
        cast(ubyte*) malloc(sampleCount);

    auto plane2 =
        cast(ubyte*) malloc(sampleCount);


    assert(plane0 !is null);
    assert(plane1 !is null);
    assert(plane2 !is null);


    foreach (index; 0 .. sampleCount)
    {
        plane0[index] =
            cast(ubyte)(index);

        plane1[index] =
            cast(ubyte)(100 + index);

        plane2[index] =
            cast(ubyte)(200 + index);
    }


    ResourceEntry[3] resources =
    [
        ResourceEntry(
            plane0,
            sampleCount,
            &releases[0],
            &releaseCounted
        ),

        ResourceEntry(
            plane1,
            sampleCount,
            &releases[1],
            &releaseCounted
        ),

        ResourceEntry(
            plane2,
            sampleCount,
            &releases[2],
            &releaseCounted
        )
    ];


    PlaneDescriptor[3] descriptors =
    [
        PlaneDescriptor(
            plane0,
            width,
            1
        ),

        PlaneDescriptor(
            plane1,
            width,
            1
        ),

        PlaneDescriptor(
            plane2,
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

        assert(releases == [0, 0, 0]);


        /*
         * Caller-side metadata no longer matters after construction.
         */
        foreach (ref resource; resources)
        {
            resource =
                ResourceEntry.init;
        }

        foreach (ref descriptor; descriptors)
        {
            descriptor =
                PlaneDescriptor.init;
        }


        auto view =
            lease.view();

        assert(view.planeCount == 3);


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


        assert(
            view.trySample(
                1,
                3,
                2,
                value
            )
        );

        assert(value == 111);


        assert(
            view.trySample(
                2,
                3,
                2,
                value
            )
        );

        assert(value == 211);


        assert(releases == [0, 0, 0]);
    }


    assert(releases == [1, 1, 1]);
}


unittest
{
    /*
     * Pixel-interleaved topology:
     *
     * three logical planes share one retained physical resource.
     *
     * Plane descriptors differ only by their starting byte while sharing:
     *
     *     rowStrideElements    = width * 3
     *     sampleStrideElements = 3
     *
     * The one physical resource must be released exactly once, not once per
     * logical plane.
     */

    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t channelCount = 3;

    enum size_t sampleCount =
        width * height * channelCount;


    size_t releases;


    auto pixels =
        cast(ubyte*) malloc(sampleCount);

    assert(pixels !is null);


    foreach (y; 0 .. height)
    {
        foreach (x; 0 .. width)
        {
            const pixel =
                (y * width + x)
                * channelCount;

            pixels[pixel + 0] =
                cast(ubyte)(
                    y * 10 + x
                );

            pixels[pixel + 1] =
                cast(ubyte)(
                    100 + y * 10 + x
                );

            pixels[pixel + 2] =
                cast(ubyte)(
                    200 + y * 10 + x
                );
        }
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


    PlaneDescriptor[3] descriptors =
    [
        PlaneDescriptor(
            pixels + 0,
            width * channelCount,
            channelCount
        ),

        PlaneDescriptor(
            pixels + 1,
            width * channelCount,
            channelCount
        ),

        PlaneDescriptor(
            pixels + 2,
            width * channelCount,
            channelCount
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


        /*
         * Poison caller metadata to ensure the retained representation uses its
         * own stable copies.
         */
        resources[0] =
            ResourceEntry.init;

        foreach (ref descriptor; descriptors)
        {
            descriptor =
                PlaneDescriptor.init;
        }


        auto view =
            lease.view();

        assert(view.planeCount == 3);


        ubyte value;


        assert(
            view.trySample(
                0,
                3,
                2,
                value
            )
        );

        assert(value == 23);


        assert(
            view.trySample(
                1,
                3,
                2,
                value
            )
        );

        assert(value == 123);


        assert(
            view.trySample(
                2,
                3,
                2,
                value
            )
        );

        assert(value == 223);


        /*
         * Additional coordinate to ensure the three affine streams remain
         * correctly interleaved over more than one pixel.
         */
        assert(
            view.trySample(
                2,
                1,
                1,
                value
            )
        );

        assert(value == 211);


        assert(releases == 0);
    }


    /*
     * One shared physical allocation means one release obligation.
     */
    assert(releases == 1);
}


} // version (unittest)
