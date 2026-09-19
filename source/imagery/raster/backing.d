/++
    Retained backing storage and lifetime capability for RasterView.

    RasterView remains a cheap non-owning semantic view.

    RasterLease retains the backing representation from which such views
    borrow their descriptor metadata and pixel resources.
+/
module imagery.raster.backing;

import core.stdc.stdlib :
    free,
    malloc;

import std.algorithm.mutation :
    move;

import std.typecons :
    SafeRefCounted,
    RefCountedAutoInitialize,
    borrow,
    safeRefCounted;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.sample :
    isRasterSampleType;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult,
    validateRasterBackingLayout;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    RasterView,
    makeRasterViewAssumeValidated;

import imagery.raster.writable_view :
    WritableRasterView,
    tryMakeWritableRasterView;


/++
    Complete retained representation underlying one raster lease.

    The backing owns:

    - zero or more physical resources;
    - one stable PlaneDescriptor block;
    - the allocations containing both metadata tables.

    RasterView itself owns none of these objects.
+/
package(imagery.raster)
struct RasterBacking(T)
{
    static assert(
        isRasterSampleType!T,
        "RasterBacking sample type must be an unqualified POD value type "
        ~ "without indirections."
    );

private:
    ResourceEntry[] resources_;

    PlaneDescriptor[] descriptors_;

    void* resourceTableAllocation_;

    void* descriptorTableAllocation_;

    Region2D fullRegion_;

public:
    @disable this(this);


    /++
        Package-internal ownership constructor.

        The supplied metadata allocations and physical resources are already
        validated and owned by the construction layer.

        After this constructor returns, this RasterBacking is responsible for:

        - every ResourceEntry release obligation;
        - resourceTableAllocation;
        - descriptorTableAllocation.

        This is not a public raw-pointer construction API.
    +/
    package(imagery.raster)
    this(
        ResourceEntry[] resources,
        PlaneDescriptor[] descriptors,
        void* resourceTableAllocation,
        void* descriptorTableAllocation,
        Region2D fullRegion
    )
    @system
    nothrow
    @nogc
    {
        resources_ =
            resources;

        descriptors_ =
            descriptors;

        resourceTableAllocation_ =
            resourceTableAllocation;

        descriptorTableAllocation_ =
            descriptorTableAllocation;

        fullRegion_ =
            fullRegion;
    }


    /++
        Releases every registered physical resource exactly once, then releases
        the backing's metadata allocations.
    +/
    ~this()
    @trusted
    nothrow
    @nogc
    {
        foreach (ref resource; resources_)
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

                resource.base = null;
            }
        }

        if (descriptorTableAllocation_ !is null)
        {
            free(descriptorTableAllocation_);

            descriptorTableAllocation_ = null;
        }

        if (resourceTableAllocation_ !is null)
        {
            free(resourceTableAllocation_);

            resourceTableAllocation_ = null;
        }
    }
}


private alias RasterBackingOwner(T) =
    SafeRefCounted!(
        RasterBacking!T,
        RefCountedAutoInitialize.no
    );


/++
    Commits an already validated RasterBacking into reference-counted retained
    ownership and returns its public lifetime capability.

    This is the final ownership transition used by the construction layer.

    Deliberately not declared `nothrow`: creation of the SafeRefCounted store is
    an allocation boundary.
+/
package(imagery.raster)
RasterLease!T retainRasterBacking(T)(
    RasterBacking!T backing
)
@trusted
{
    auto owner =
        safeRefCounted(
            move(backing)
        );

    return RasterLease!T(
        move(owner)
    );
}


/++
    Converts an already retained and validated backing into its semantic
    non-owning RasterView.

    `return ref` propagates the descriptor/resource borrow from `backing` into
    the returned view.
+/
private
RasterView!T makeViewFromBacking(T)(
    return ref RasterBacking!T backing
)
@safe
pure
nothrow
@nogc
{
    return makeRasterViewAssumeValidated!T(
        backing.descriptors_,
        backing.fullRegion_
    );
}


/++
    Attempts to derive a semantic writable view from one already-retained
    RasterBacking.

    Lifetime of the returned view remains tied to `backing`.

    The backing entered retained ownership only after ordinary validation.
    E5.4d.1c nevertheless deliberately reuses the existing complete writable
    factory instead of introducing a second assume-validated construction
    boundary.

    This keeps writable capability creation behind the established sequence:

        ordinary validation
            ->
        writable certification
            ->
        semantic writable view

    The duplicate ordinary validation is control-plane work and may only be
    optimized later if evidence shows that it matters.
+/
private
WritableRasterView!T makeWritableViewFromBacking(T)(
    return ref RasterBacking!T backing
)
@safe
nothrow
@nogc
{
    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    return tryMakeWritableRasterView!T(
        backing.resources_,
        backing.descriptors_,
        backing.fullRegion_,
        validation,
        certification
    );
}


/++
    Lifetime capability for a retained raster representation.

    Copying a RasterLease retains the same backing representation.

    A RasterView obtained from `view()` borrows from this lease and therefore
    must not outlive it.
+/
struct RasterLease(T)
{
    static assert(
        isRasterSampleType!T,
        "RasterLease sample type must be an unqualified POD value type "
        ~ "without indirections."
    );

private:
    RasterBackingOwner!T owner_;

    package(imagery.raster)
    this(RasterBackingOwner!T owner)
    @trusted
    nothrow
    @nogc
    {
        owner_ = move(owner);
    }

public:

    /++
        Returns true when this lease currently retains a RasterBacking.

        Package-internal construction/control-plane query.

        This deliberately checks the SafeRefCounted store without accessing
        its payload, so RasterLease.init can be inspected safely.
    +/
    package(imagery.raster)
    @property
    bool hasBacking() const
    @safe
    nothrow
    {
        return owner_.refCountedStore.isInitialized;
    }


    /++
        Returns a non-owning read-only RasterView borrowing from this lease.
    +/
    RasterView!T view()
    return
    @trusted
    nothrow
    @nogc
    {
        return owner_.borrow!(
            makeViewFromBacking!T
        );
    }


    /++
        Attempts to return a non-owning writable semantic view borrowing from
        this lease.

        This operation is deliberately package-internal while
        WritableRasterView itself remains package-internal.

        A mutable RasterLease receiver is required. A const lease must not be
        usable to recover write capability.

        `success` is false for:

        - RasterLease.init / an uninitialized retained owner;
        - invalid retained metadata detected defensively by the reused factory;
        - a backing whose represented planes are not completely covered by
          retained readWrite resources.

        On failure WritableRasterView.init is returned.

        On success the returned WritableRasterView remains lifetime-bound to
        this lease exactly as RasterView returned by view() is.

        Writable capability does not imply uniqueness, exclusivity, noalias,
        contiguity, non-overlap, or thread exclusivity.
    +/
    package(imagery.raster)
    WritableRasterView!T tryWritableView(
        out bool success
    )
    return
    @trusted
    nothrow
    @nogc
    {
        success = false;

        if (!owner_.refCountedStore.isInitialized)
        {
            return WritableRasterView!T.init;
        }


        scope auto view =
            owner_.borrow!(
                makeWritableViewFromBacking!T
            );

        /*
         * Ordinary backing validation requires at least one logical plane.
         *
         * Therefore:
         *
         *     successful writable view -> planeCount > 0
         *     failed factory           -> WritableRasterView.init
         *                              -> planeCount == 0
         *
         * This remains true for geometrically empty rasters: an empty
         * Region2D still retains its logical plane metadata.
         */
        success =
            view.planeCount != 0;

        return view;
    }
}


version (unittest)
{

import imagery.raster.resource :
    ResourceAccess;


/*
 * The remaining declarations are test-only helpers.
 *
 * They construct known-valid storage so the production lifetime model can be
 * exercised without yet exposing a public raw-pointer import API.
 */


/++
    Counts one release and frees the physical allocation.
+/
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


/++
    Creates a valid three-plane 4 x 3 ubyte backing.

    Each plane is an independent allocation.

    Logical sample values use:

        band * 100 + y * 10 + x
+/
private
@trusted
RasterBacking!ubyte makeLifetimeTestBacking(
    size_t* releaseCounters
)
{
    enum size_t planeCount = 3;
    enum size_t width = 4;
    enum size_t height = 3;
    enum size_t planeSamples = width * height;

    const resourceBytes =
        planeCount * ResourceEntry.sizeof;

    const descriptorBytes =
        planeCount * PlaneDescriptor.sizeof;

    void* resourceMemory =
        malloc(resourceBytes);

    void* descriptorMemory =
        malloc(descriptorBytes);

    assert(resourceMemory !is null);
    assert(descriptorMemory !is null);

    auto resources =
        (cast(ResourceEntry*) resourceMemory)
        [0 .. planeCount];

    auto descriptors =
        (cast(PlaneDescriptor*) descriptorMemory)
        [0 .. planeCount];

    foreach (band; 0 .. planeCount)
    {
        void* planeMemory =
            malloc(planeSamples * ubyte.sizeof);

        assert(planeMemory !is null);

        auto samples =
            (cast(ubyte*) planeMemory)
            [0 .. planeSamples];

        foreach (y; 0 .. height)
        {
            foreach (x; 0 .. width)
            {
                samples[
                    y * width + x
                ] = cast(ubyte)(
                    band * 100
                    + y * 10
                    + x
                );
            }
        }

        resources[band] =
            ResourceEntry(
                planeMemory,
                planeSamples * ubyte.sizeof,
                releaseCounters + band,
                &releaseCounted
            );

        descriptors[band] =
            PlaneDescriptor(
                planeMemory,
                cast(ptrdiff_t) width,
                1
            );
    }

    RasterBacking!ubyte backing;

    backing.resources_ = resources;
    backing.descriptors_ = descriptors;

    backing.resourceTableAllocation_ =
        resourceMemory;

    backing.descriptorTableAllocation_ =
        descriptorMemory;

    backing.fullRegion_ =
        Region2D(
            0,
            0,
            width,
            height
        );

    const validation =
        validateRasterBackingLayout!ubyte(
            backing.resources_,
            backing.descriptors_,
            backing.fullRegion_
        );

    assert(validation.ok);

    return move(backing);
}


/++
    Test-only Lease factory also used by compile-negative probes.
+/
@trusted
RasterLease!ubyte makeLifetimeTestLease(
    size_t* releaseCounters
)
{
    auto backing =
        makeLifetimeTestBacking(
            releaseCounters
        );

    auto owner =
        safeRefCounted(
            move(backing)
        );

    return RasterLease!ubyte(
        move(owner)
    );
}


/++
    Creates the same lifetime-test backing with explicit retained write access.

    The ordinary makeLifetimeTestLease helper deliberately remains read-only so
    tests cover both certification failure and success.
+/
@trusted
RasterLease!ubyte makeWritableLifetimeTestLease(
    size_t* releaseCounters
)
{
    auto backing =
        makeLifetimeTestBacking(
            releaseCounters
        );

    foreach (ref resource; backing.resources_)
    {
        resource.access =
            ResourceAccess.readWrite;
    }


    auto owner =
        safeRefCounted(
            move(backing)
        );

    return RasterLease!ubyte(
        move(owner)
    );
}


unittest
{
    size_t[3] releases =
        [0, 0, 0];

    {
        auto lease =
            makeLifetimeTestLease(
                releases.ptr
            );

        assert(
            releases[]
            == [0, 0, 0]
        );

        auto view =
            lease.view();

        assert(view.planeCount == 3);
        assert(view.width == 4);
        assert(view.height == 3);

        ubyte value;

        assert(
            view.trySample(
                1,
                2,
                1,
                value
            )
        );

        assert(value == 112);


        bool roiSuccess;

        auto roi =
            view.tryRoi(
                Region2D(
                    1,
                    1,
                    2,
                    2
                ),
                roiSuccess
            );

        assert(roiSuccess);

        assert(
            roi.trySample(
                2,
                1,
                1,
                value
            )
        );

        assert(value == 222);


        /*
         * A second lease retains the same backing.
         */
        {
            auto secondLease =
                lease;

            auto secondView =
                secondLease.view();

            assert(
                secondView.trySample(
                    0,
                    3,
                    2,
                    value
                )
            );

            assert(value == 23);

            assert(
                releases[]
                == [0, 0, 0]
            );
        }

        /*
         * Destroying the copy must not release the resources while the
         * original lease remains alive.
         */
        assert(
            releases[]
            == [0, 0, 0]
        );
    }

    /*
     * The final lease has gone away: every independent resource must now have
     * been released exactly once.
     */
    assert(
        releases[]
        == [1, 1, 1]
    );
}


unittest
{
    /*
     * A copied lease can outlive the original lease and continue to retain
     * the backing representation.
     */

    size_t[3] releases =
        [0, 0, 0];

    RasterLease!ubyte survivor;

    {
        auto original =
            makeLifetimeTestLease(
                releases.ptr
            );

        survivor =
            original;
    }

    assert(
        releases[]
        == [0, 0, 0]
    );


    {
        auto view =
            survivor.view();

        ubyte value;

        assert(
            view.trySample(
                2,
                3,
                2,
                value
            )
        );

        assert(value == 223);
    }


    survivor =
        RasterLease!ubyte.init;

    assert(
        releases[]
        == [1, 1, 1]
    );
}



unittest
{
    /*
     * The ordinary lifetime-test backing carries default read-only access.
     *
     * It remains readable but must not publish writable capability.
     */
    size_t[3] releases =
        [0, 0, 0];

    {
        auto lease =
            makeLifetimeTestLease(
                releases.ptr
            );

        bool success = true;

        scope auto writable =
            lease.tryWritableView(
                success
            );

        assert(!success);
        assert(writable.planeCount == 0);

        auto readable =
            lease.view();

        ubyte value;

        assert(
            readable.trySample(
                1,
                2,
                1,
                value
            )
        );

        assert(value == 112);
    }

    assert(
        releases[]
        == [1, 1, 1]
    );
}


unittest
{
    /*
     * Explicit readWrite provenance may publish a lease-bound writable view.
     *
     * Mutation through that view is immediately observable through an ordinary
     * read-only view of the same retained backing. No uniqueness is implied.
     */
    size_t[3] releases =
        [0, 0, 0];

    {
        auto lease =
            makeWritableLifetimeTestLease(
                releases.ptr
            );

        bool success;

        scope auto writable =
            lease.tryWritableView(
                success
            );

        assert(success);
        assert(writable.planeCount == 3);
        assert(writable.width == 4);
        assert(writable.height == 3);

        assert(
            writable.trySetSample(
                1,
                2,
                1,
                199
            )
        );


        auto readable =
            lease.view();

        ubyte value;

        assert(
            readable.trySample(
                1,
                2,
                1,
                value
            )
        );

        assert(value == 199);


        bool roiSuccess;

        scope auto roi =
            writable.tryRoi(
                Region2D(
                    1,
                    1,
                    2,
                    2
                ),
                roiSuccess
            );

        assert(roiSuccess);

        assert(
            roi.trySetSample(
                2,
                1,
                1,
                231
            )
        );

        assert(
            readable.trySample(
                2,
                2,
                2,
                value
            )
        );

        assert(value == 231);
    }

    assert(
        releases[]
        == [1, 1, 1]
    );
}


unittest
{
    /*
     * The fallible lease API handles RasterLease.init without entering
     * SafeRefCounted.borrow on an uninitialized store.
     */
    RasterLease!ubyte lease;

    bool success = true;

    scope auto writable =
        lease.tryWritableView(
            success
        );

    assert(!success);
    assert(writable.planeCount == 0);
}


} // version (unittest)
