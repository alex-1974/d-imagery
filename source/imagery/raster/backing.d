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

import imagery.raster.validation :
    validateRasterBackingLayout;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    RasterView,
    makeRasterViewAssumeValidated;


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
private:
    ResourceEntry[] resources_;

    PlaneDescriptor[] descriptors_;

    void* resourceTableAllocation_;

    void* descriptorTableAllocation_;

    Region2D fullRegion_;

public:
    @disable this(this);


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
    Lifetime capability for a retained raster representation.

    Copying a RasterLease retains the same backing representation.

    A RasterView obtained from `view()` borrows from this lease and therefore
    must not outlive it.
+/
struct RasterLease(T)
{
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
}


version (unittest)
{

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


} // version (unittest)
