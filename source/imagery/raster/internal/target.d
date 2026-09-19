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

import imagery.raster.internal.execution_layout :
    PlaneExecutionTraits;

import imagery.raster.writable_view :
    WritableRasterView;


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
    Materializes a mutable slice over an already-certified execution range.

    The caller has already established that `base` is the first reachable
    writable sample and that `elementCount` describes a completely reachable
    contiguous range.

    This is the single target-layer trusted boundary required to convert the
    mutable execution pointer into D slice metadata.

    It establishes no uniqueness or non-aliasing property.
+/
private
T[] makeWritableExecutionSlice(T)(
    return scope T* base,
    size_t elementCount
)
@trusted
nothrow
@nogc
{
    return base[0 .. elementCount];
}


/++
    Derives the existing contiguous writable execution target from one plane
    of a certified WritableRasterView.

    Empty views are valid targets regardless of execution-layout
    classification because no sample is reachable and no physical pointer is
    required.

    Non-empty views require the existing flat Contiguous 1D execution
    capability.

    On failure `success` is false and RasterTargetPlane.init is returned.

    The returned target remains lifetime-bound to `view`.

    This operation establishes no uniqueness, exclusivity, noalias,
    source/target non-overlap or thread-exclusivity property.
+/
package(imagery.raster)
RasterTargetPlane!T tryBorrowContiguousTarget(T)(
    return scope ref WritableRasterView!T view,
    size_t planeIndex,
    out bool success
)
@safe
nothrow
@nogc
{
    success = false;

    PlaneExecutionTraits traits;

    if (
        !view.tryPlaneExecutionTraits(
            planeIndex,
            traits
        )
    )
    {
        return RasterTargetPlane!T.init;
    }


    /*
     * Empty is a semantic case rather than a non-empty storage capability.
     *
     * In particular, executionRegionBase() must not be called here.
     */
    if (view.empty)
    {
        return tryBorrowContiguousTarget!T(
            T[].init,
            view.width,
            view.height,
            success
        );
    }


    if (!traits.linearContiguous1D)
    {
        return RasterTargetPlane!T.init;
    }


    /*
     * Do not add local `scope` here.
     *
     * DIP1000 must preserve the provenance from the return-scope view through
     * these derived aliases to the returned RasterTargetPlane.
     */
    auto base =
        view.executionRegionBase(
            planeIndex
        );

    assert(base !is null);
    assert(traits.flatElementCount != 0);


    auto storage =
        makeWritableExecutionSlice!T(
            base,
            traits.flatElementCount
        );


    /*
     * Reuse the established target constructor so its dimension/count
     * invariants remain the single implementation.
     */
    return tryBorrowContiguousTarget!T(
        storage,
        view.width,
        view.height,
        success
    );
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

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceAccess,
    ResourceEntry;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult;

import imagery.raster.writable_view :
    tryMakeWritableRasterView;


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


/*
 * A certified flat-contiguous writable view derives the existing target
 * capability and mutations through that target reach the backing samples.
 */
unittest
{
    ubyte[8] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                4,
                2
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            view,
            0,
            success
        );

    assert(success);
    assert(target.width == 4);
    assert(target.height == 2);
    assert(target.elementCount == 8);
    assert(!target.empty);

    assert(
        target.executionBase()
        == samples.ptr
    );

    target.executionBase()[3] = 71;

    assert(samples[3] == 71);
}


/*
 * Unit-X storage with padded rows is Canonical, not flat contiguous, and
 * therefore does not derive RasterTargetPlane.
 */
unittest
{
    ubyte[10] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            5,
            1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                4,
                2
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);

    bool success;

    auto derived =
        tryBorrowContiguousTarget(
            view,
            0,
            success
        );

    assert(!success);
    assert(derived.empty);
    assert(derived.elementCount == 0);
}


/*
 * General affine / negative-stride writable storage remains outside the
 * contiguous target capability.
 */
unittest
{
    ubyte[8] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 3,
            4,
            -1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                4,
                2
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);

    bool success;

    auto derived =
        tryBorrowContiguousTarget(
            view,
            0,
            success
        );

    assert(!success);
    assert(derived.empty);
}


/*
 * An empty valid writable plane produces a valid empty target while preserving
 * logical dimensions and without forming a mutable execution pointer.
 */
unittest
{
    ubyte[1] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            1,
            1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                0,
                7
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);
    assert(view.empty);

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            view,
            0,
            success
        );

    assert(success);
    assert(target.width == 0);
    assert(target.height == 7);
    assert(target.elementCount == 0);
    assert(target.empty);
    assert(target.executionBase() is null);
}


/*
 * Invalid logical plane selection is rejected before target construction.
 */
unittest
{
    ubyte[4] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto view =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            view,
            1,
            success
        );

    assert(!success);
    assert(target.empty);
}


/*
 * Classification applies to the current ROI.
 *
 * A one-row ROI may therefore become flat contiguous even though its inherited
 * row stride is wider than the ROI width.
 */
unittest
{
    ubyte[12] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readWrite
        )
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    BackingValidationResult validation;
    WritableBackingCertificationResult certification;

    auto parent =
        tryMakeWritableRasterView!ubyte(
            resources[],
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            ),
            validation,
            certification
        );

    assert(validation.ok);
    assert(certification.ok);

    bool roiSuccess;

    auto child =
        parent.tryRoi(
            Region2D(
                1,
                1,
                2,
                1
            ),
            roiSuccess
        );

    assert(roiSuccess);

    bool targetSuccess;

    auto target =
        tryBorrowContiguousTarget(
            child,
            0,
            targetSuccess
        );

    assert(targetSuccess);
    assert(target.width == 2);
    assert(target.height == 1);
    assert(target.elementCount == 2);

    assert(
        target.executionBase()
        == samples.ptr + 5
    );

    target.executionBase()[1] = 99;

    assert(samples[6] == 99);
}

}
