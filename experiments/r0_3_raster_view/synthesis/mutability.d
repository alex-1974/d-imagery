module synthesis.mutability;


/*
 * Physical plane metadata.
 *
 * Pixel access rights deliberately do not live in this descriptor.
 * One stable descriptor block can therefore be shared by read-only and
 * writable views.
 */
struct PlaneDescriptor
{
    const(void)* base;

    ptrdiff_t rowStrideElements;
    ptrdiff_t sampleStrideElements;
}


struct Region2D
{
    size_t x;
    size_t y;
    size_t width;
    size_t height;
}


/*
 * Read-only pixel capability.
 */
struct RasterView(T)
{
private:

    const(PlaneDescriptor)[] planes_;
    Region2D region_;

public:

    @property
    size_t planeCount() const
    nothrow
    @nogc
    {
        return planes_.length;
    }


    @property
    Region2D region() const
    nothrow
    @nogc
    {
        return region_;
    }


    const(T)* planeBase(
        size_t planeIndex
    )
    return scope
    @trusted
    nothrow
    @nogc
    {
        assert(planeIndex < planes_.length);

        auto descriptor =
            planes_[planeIndex];

        auto base =
            cast(const(T)*)descriptor.base;

        return base
            + cast(ptrdiff_t)region_.y
                * descriptor.rowStrideElements
            + cast(ptrdiff_t)region_.x
                * descriptor.sampleStrideElements;
    }


    RasterView!T roi(
        size_t x,
        size_t y,
        size_t width,
        size_t height
    )
    return scope
    nothrow
    @nogc
    {
        assert(x <= region_.width);
        assert(y <= region_.height);
        assert(width <= region_.width - x);
        assert(height <= region_.height - y);

        return RasterView!T(
            planes_,
            Region2D(
                region_.x + x,
                region_.y + y,
                width,
                height
            )
        );
    }
}


/*
 * Writable pixel capability.
 *
 * Construction must remain inside the trusted backing/lease boundary in the
 * final implementation.  The experiment constructs it through factory code
 * in this module.
 */
struct MutableRasterView(T)
{
private:

    const(PlaneDescriptor)[] planes_;
    Region2D region_;

public:

    @property
    size_t planeCount() const
    nothrow
    @nogc
    {
        return planes_.length;
    }


    @property
    Region2D region() const
    nothrow
    @nogc
    {
        return region_;
    }


    T* planeBase(
        size_t planeIndex
    )
    return scope
    @trusted
    nothrow
    @nogc
    {
        assert(planeIndex < planes_.length);

        auto descriptor =
            planes_[planeIndex];

        /*
         * The final constructor must guarantee that this descriptor belongs
         * to writable storage retained by the originating lease.
         */
        auto base =
            cast(T*)descriptor.base;

        return base
            + cast(ptrdiff_t)region_.y
                * descriptor.rowStrideElements
            + cast(ptrdiff_t)region_.x
                * descriptor.sampleStrideElements;
    }


    MutableRasterView!T roi(
        size_t x,
        size_t y,
        size_t width,
        size_t height
    )
    return scope
    nothrow
    @nogc
    {
        assert(x <= region_.width);
        assert(y <= region_.height);
        assert(width <= region_.width - x);
        assert(height <= region_.height - y);

        return MutableRasterView!T(
            planes_,
            Region2D(
                region_.x + x,
                region_.y + y,
                width,
                height
            )
        );
    }


    RasterView!T readOnly()
    return scope
    nothrow
    @nogc
    {
        return RasterView!T(
            planes_,
            region_
        );
    }
}


/*
 * Experiment-only construction boundary.
 *
 * In production these responsibilities belong to RasterLease / validated
 * backing construction rather than to public free functions.
 */
@trusted
RasterView!T makeReadView(T)(
    return scope const(PlaneDescriptor)[] planes,
    Region2D region
)
nothrow
@nogc
{
    return RasterView!T(
        planes,
        region
    );
}


@trusted
MutableRasterView!T makeMutableView(T)(
    return scope const(PlaneDescriptor)[] planes,
    Region2D region
)
nothrow
@nogc
{
    return MutableRasterView!T(
        planes,
        region
    );
}
/*
 * Experiment-only descriptor identity check.
 *
 * This is deliberately @trusted because direct pointer extraction from a
 * dynamic array is not part of the public safe API we are designing.
 *
 * It exists only to prove that Mutable -> ReadOnly is an O(1) capability
 * downgrade and does not rebuild the descriptor block.
 */
@trusted
bool sharesDescriptorBlock(T)(
    scope ref MutableRasterView!T writable,
    scope ref RasterView!T readable
)
nothrow
@nogc
{
    return
        writable.planes_.ptr
        is
        readable.planes_.ptr;
}


@trusted
bool sharesDescriptorBlock(T)(
    scope ref MutableRasterView!T first,
    scope ref MutableRasterView!T second
)
nothrow
@nogc
{
    return
        first.planes_.ptr
        is
        second.planes_.ptr;
}


@trusted
bool sharesDescriptorBlock(T)(
    scope ref RasterView!T first,
    scope ref RasterView!T second
)
nothrow
@nogc
{
    return
        first.planes_.ptr
        is
        second.planes_.ptr;
}
