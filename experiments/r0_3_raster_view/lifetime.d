module lifetime;

import core.stdc.stdlib : malloc, free;

import std.algorithm.mutation : move;
import std.stdio : writeln;
import std.typecons :
    SafeRefCounted,
    RefCountedAutoInitialize,
    safeRefCounted,
    borrow;

import views :
    PlaneDescriptor,
    MultiPlaneRasterView;


/*
 * Generic retained resource.
 *
 * RasterBacking does not need to know what kind of resource this is.
 */
alias ReleaseFn =
    void function(
        void* context,
        void* base,
        size_t byteLength
    )
    nothrow
    @nogc;


struct ResourceEntry
{
    void* base;
    size_t byteLength;

    void* releaseContext;
    ReleaseFn releaseFn;
}


/*
 * One retained raster representation.
 *
 * It owns:
 *
 * - zero or more independent backing resources;
 * - one stable descriptor block.
 *
 * RasterView will borrow only the descriptor slice.
 */
struct RasterBacking
{
    ResourceEntry[] resources;
    PlaneDescriptor!float[] descriptors;

    void* resourceTableAllocation;
    void* descriptorTableAllocation;

    size_t width;
    size_t height;

    @disable this(this);

    ~this() @trusted nothrow @nogc
    {
        foreach (ref resource; resources)
        {
            if (
                resource.base !is null &&
                resource.releaseFn !is null
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

        if (descriptorTableAllocation !is null)
        {
            free(descriptorTableAllocation);
            descriptorTableAllocation = null;
        }

        if (resourceTableAllocation !is null)
        {
            free(resourceTableAllocation);
            resourceTableAllocation = null;
        }
    }
}


alias RasterBackingOwner =
    SafeRefCounted!(
        RasterBacking,
        RefCountedAutoInitialize.no
    );


/*
 * Count the release and then free the actual backing allocation.
 */
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


/*
 * Build three physically independent float planes.
 *
 * The trusted boundary is responsible for validating and constructing
 * slices from raw malloc-backed memory.
 */
@trusted
RasterBacking makePlanarRGBBacking(
    size_t width,
    size_t height,
    size_t* releaseCounters
)
{
    enum size_t planeCount = 3;

    const resourceBytes =
        planeCount * ResourceEntry.sizeof;

    const descriptorBytes =
        planeCount * PlaneDescriptor!float.sizeof;


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
        (cast(PlaneDescriptor!float*) descriptorMemory)
        [0 .. planeCount];


    const planeBytes =
        width *
        height *
        float.sizeof;


    foreach (i; 0 .. planeCount)
    {
        void* planeMemory =
            malloc(planeBytes);

        assert(planeMemory !is null);


        resources[i] =
            ResourceEntry(
                planeMemory,
                planeBytes,
                releaseCounters + i,
                &releaseCounted
            );


        descriptors[i] =
            PlaneDescriptor!float(
                cast(float*) planeMemory,
                cast(ptrdiff_t) width,
                1
            );
    }


    return RasterBacking(
        resources,
        descriptors,
        resourceMemory,
        descriptorMemory,
        width,
        height
    );
}


/*
 * Safe semantic conversion from a retained backing representation to a
 * non-owning RasterView.
 *
 * `return ref` expresses that aliases in the returned view originate from
 * the backing object.
 */
@safe
MultiPlaneRasterView!float makeViewFromBacking(
    return ref RasterBacking backing
)
{
    return MultiPlaneRasterView!float(
        backing.descriptors,
        backing.width,
        backing.height,
        0,
        0
    );
}


/*
 * RasterLease retains the representation.
 *
 * The returned RasterView remains non-owning and its lifetime is bound to
 * this lease by DIP1000.
 */
struct RasterLease
{
    private RasterBackingOwner owner_;

    MultiPlaneRasterView!float view()
    return
    @trusted
    {
        return owner_.borrow!makeViewFromBacking;
    }
}


/*
 * Convenience factory used by positive and negative lifetime probes.
 *
 * This creates one complete retained representation and returns only the
 * owning lease.  Views must subsequently borrow from that lease.
 */
@trusted
RasterLease makeTestLease(
    size_t* releaseCounters,
    size_t width = 64,
    size_t height = 32
)
{
    auto backing =
        makePlanarRGBBacking(
            width,
            height,
            releaseCounters
        );

    auto owner =
        safeRefCounted(
            move(backing)
        );

    return RasterLease(
        move(owner)
    );
}



void main()
{
    size_t[3] releases = [0, 0, 0];


    {
        auto backing =
            makePlanarRGBBacking(
                64,
                32,
                releases.ptr
            );


        auto owner =
            safeRefCounted(
                move(backing)
            );


        auto lease =
            RasterLease(
                move(owner)
            );


        /*
         * A RasterView borrows descriptor metadata.
         */
        auto view =
            lease.view();

        assert(view.planeCount == 3);
        assert(view.width == 64);
        assert(view.height == 32);

        assert(releases[] == [0, 0, 0]);


        /*
         * ROI must keep using the exact same descriptor block.
         */
        auto roi =
            view.roi(
                7,
                5,
                23,
                11
            );

        assert(
            roi.planes.ptr
            is
            view.planes.ptr
        );

        assert(roi.width == 23);
        assert(roi.height == 11);


        /*
         * Copying the lease retains the whole representation.
         */
        {
            auto secondLease =
                lease;

            auto secondView =
                secondLease.view();

            assert(secondView.planeCount == 3);

            assert(
                secondView.planes.ptr
                is
                view.planes.ptr
            );

            assert(releases[] == [0, 0, 0]);
        }


        /*
         * The original lease still keeps every resource alive.
         */
        assert(releases[] == [0, 0, 0]);

        writeln(
            "retained descriptors/resources: PASS"
        );
    }


    /*
     * Final lease disappeared:
     *
     * every independent plane must now have been released exactly once.
     */
    assert(releases[] == [1, 1, 1]);

    writeln(
        "final release exactly once: PASS"
    );

    writeln(
        "R0.3 descriptor lifetime positive probe: PASS"
    );
}
