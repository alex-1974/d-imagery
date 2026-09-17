/++
    Internal writable raster-target semantics.

    RasterTargetPlane is deliberately separate from RasterView:

    - RasterView is read-only input;
    - RasterTargetPlane is writable output;
    - neither type implies unique ownership;
    - neither type promises source/target non-aliasing.

    The initial E3b construction capability is intentionally limited to
    contiguous single-plane storage. The type itself remains an internal
    semantic target so additional validated layouts can be added later without
    exposing Mir through the raster API.
+/
module imagery.raster.internal.target;


/++
    Non-owning writable single-plane raster target.

    Copies of this value may alias the same storage. This type provides memory
    safety and lifetime tracking, not uniqueness.
+/
package(imagery.raster)
struct RasterTargetPlane(T)
{
private:
    T[] storage_;

    size_t width_;
    size_t height_;

    size_t elementCount_;


    this(
        return scope T[] storage,
        size_t width,
        size_t height,
        size_t elementCount
    )
    @safe
    nothrow
    @nogc
    {
        storage_ = storage;

        width_ = width;
        height_ = height;

        elementCount_ = elementCount;
    }


public:
    @property
    size_t width() const
    @safe
    pure
    nothrow
    @nogc
    {
        return width_;
    }


    @property
    size_t height() const
    @safe
    pure
    nothrow
    @nogc
    {
        return height_;
    }


    @property
    bool empty() const
    @safe
    pure
    nothrow
    @nogc
    {
        return width_ == 0
            || height_ == 0;
    }


    @property
    size_t elementCount() const
    @safe
    pure
    nothrow
    @nogc
    {
        return elementCount_;
    }


    /++
        Internal execution base for the current contiguous target.

        Empty targets return null without indexing storage. For non-empty
        targets construction has already proved that at least element zero is
        reachable.
    +/
    package(imagery.raster)
    T* executionBase()
    return scope
    @safe
    nothrow
    @nogc
    {
        if (empty)
            return null;

        return &storage_[0];
    }
}


/++
    Borrows a contiguous writable target from caller-owned storage.

    The logical target dimensions are preserved for empty targets.

    For a non-empty target:

        elementCount = width * height

    must be representable in size_t and no greater than storage.length.

    Extra caller storage beyond elementCount is deliberately excluded from the
    returned target.

    On failure, success is false and RasterTargetPlane.init is returned.
+/
package(imagery.raster)
RasterTargetPlane!T tryBorrowContiguousTarget(T)(
    return scope T[] storage,
    size_t width,
    size_t height,
    out bool success
)
@safe
nothrow
@nogc
{
    success = false;

    if (
        height != 0
        && width > size_t.max / height
    )
    {
        return RasterTargetPlane!T.init;
    }

    const elementCount =
        width * height;

    if (elementCount > storage.length)
        return RasterTargetPlane!T.init;

    success = true;

    return RasterTargetPlane!T(
        storage[0 .. elementCount],
        width,
        height,
        elementCount
    );
}


version (unittest)
{

/*
 * Normal target construction preserves dimensions and restricts the borrowed
 * storage to exactly the logical element count.
 */
unittest
{
    int[8] storage =
        [0, 1, 2, 3, 4, 5, 6, 7];

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[],
            3,
            2,
            success
        );

    assert(success);

    assert(target.width == 3);
    assert(target.height == 2);
    assert(target.elementCount == 6);

    assert(!target.empty);
    assert(target.executionBase() == &storage[0]);
}


/*
 * Insufficient storage is rejected.
 */
unittest
{
    int[5] storage;

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[],
            3,
            2,
            success
        );

    assert(!success);

    assert(target.width == 0);
    assert(target.height == 0);
    assert(target.elementCount == 0);
    assert(target.empty);
}


/*
 * Multiplication overflow is rejected before width * height is evaluated.
 */
unittest
{
    int[1] storage;

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[],
            size_t.max,
            2,
            success
        );

    assert(!success);
    assert(target.empty);
}


/*
 * Either zero dimension produces a valid empty target. Dimensions remain
 * semantic information even though no storage is reachable.
 */
unittest
{
    int[] storage;

    bool success;

    auto zeroWidth =
        tryBorrowContiguousTarget(
            storage,
            0,
            size_t.max,
            success
        );

    assert(success);
    assert(zeroWidth.width == 0);
    assert(zeroWidth.height == size_t.max);
    assert(zeroWidth.elementCount == 0);
    assert(zeroWidth.empty);
    assert(zeroWidth.executionBase() is null);


    auto zeroHeight =
        tryBorrowContiguousTarget(
            storage,
            size_t.max,
            0,
            success
        );

    assert(success);
    assert(zeroHeight.width == size_t.max);
    assert(zeroHeight.height == 0);
    assert(zeroHeight.elementCount == 0);
    assert(zeroHeight.empty);
    assert(zeroHeight.executionBase() is null);
}

}
