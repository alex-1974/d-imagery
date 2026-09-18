/++
    Package-internal semantic writable raster view.

    WritableRasterView is deliberately separate from ownership and retained
    resource metadata.

    Construction is permitted only after the represented raster region has
    already been certified writable from retained ResourceAccess provenance.

    The type means:

        writes through this view are permitted

    It does not mean:

        unique
        exclusive
        non-aliasing
        contiguous
        single-plane
        thread-exclusive

    PlaneDescriptor remains access-neutral and continues to store
    const(void)*. Mutable typed access is formed only inside the narrow trusted
    sample-write boundary below.

    This module remains package-internal during E5.4d.1.
+/
module imagery.raster.writable_view;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.resource :
    ResourceEntry;

import imagery.raster.sample :
    isRasterSampleType;

import imagery.raster.validation :
    BackingValidationResult,
    WritableBackingCertificationResult,
    certifyWritableRasterBacking,
    validateRasterBackingLayout;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/++
    Non-owning writable semantic raster view.

    Plane order is logical band order.

    Region coordinates belong to the resident descriptor-space coordinate
    system used by the stable PlaneDescriptor block.

    The view owns neither descriptors nor pixel storage.
+/
package(imagery.raster)
struct WritableRasterView(T)
{
    static assert(
        isRasterSampleType!T,
        "WritableRasterView sample type must be an unqualified POD value "
        ~ "type without indirections."
    );


private:

    const(PlaneDescriptor)[] planes_;

    Region2D region_;


public:

    /++
        Number of logical planes/bands represented by this view.
    +/
    @property
    size_t planeCount() const
    @safe
    pure
    nothrow
    @nogc
    {
        return planes_.length;
    }


    /++
        Resident descriptor-space region represented by this view.
    +/
    @property
    Region2D region() const
    @safe
    pure
    nothrow
    @nogc
    {
        return region_;
    }


    /++
        Resident width.
    +/
    @property
    size_t width() const
    @safe
    pure
    nothrow
    @nogc
    {
        return region_.width;
    }


    /++
        Resident height.
    +/
    @property
    size_t height() const
    @safe
    pure
    nothrow
    @nogc
    {
        return region_.height;
    }


    /++
        Whether the represented region has zero area.
    +/
    @property
    bool empty() const
    @safe
    pure
    nothrow
    @nogc
    {
        return region_.empty();
    }


    /++
        Attempts to create a writable child ROI relative to this view.

        Writable certification is inherited because every reachable child
        sample is a subset of the already-certified parent sample set.

        This method deliberately requires a mutable receiver. A
        const-qualified WritableRasterView must not be usable to recover a new
        writable child capability.

        On failure `success` is false and WritableRasterView.init is returned.
    +/
    WritableRasterView!T tryRoi(
        Region2D relative,
        out bool success
    )
    return scope
    @safe
    pure
    nothrow
    @nogc
    {
        success = false;

        Region2D resolved;

        if (
            !region_.tryResolveRelative(
                relative,
                resolved
            )
        )
        {
            return WritableRasterView!T.init;
        }


        success = true;

        return makeWritableRasterViewAssumeCertified!T(
            planes_,
            resolved
        );
    }


    /++
        Attempts to read one logical sample.

        Read semantics intentionally reuse RasterView's already-established
        checked semantic accessor rather than duplicating read-side address
        arithmetic.

        Coordinates are relative to this view.

        On failure `value` is reset to T.init.

        The method is `scope` with respect to its implicit `this` borrow.
        Reading may create temporary aliases internally, but none may escape
        the call.
    +/
    bool trySample(
        size_t band,
        size_t x,
        size_t y,
        out T value
    ) const scope
    @safe
    nothrow
    @nogc
    {
        scope auto readView =
            makeRasterViewAssumeValidated!T(
                planes_,
                region_
            );

        return readView.trySample(
            band,
            x,
            y,
            value
        );
    }


    /++
        Attempts to write one logical sample.

        Coordinates are relative to this view.

        Returns false without writing when the band or coordinates are outside
        the represented view.

        This is the narrow trusted mutable sample-access boundary.

        Safety argument:

        - creation of WritableRasterView is restricted to a package boundary
          whose caller has already certified complete writable resource
          coverage;
        - ordinary retained-backing validation already proved descriptor
          alignment, coordinate representation, stride-product arithmetic,
          combined offsets, and physical reachability;
        - a child ROI can only narrow that already-certified sample set;
        - the bounds checks below keep x/y inside the certified Region2D;
        - the cast from access-neutral const(void)* to T* consumes the
          previously established writable capability; it does not create that
          capability.

        The type promises no uniqueness or non-aliasing.
    +/
    bool trySetSample(
        size_t band,
        size_t x,
        size_t y,
        T value
    )
    @trusted
    nothrow
    @nogc
    {
        if (band >= planes_.length)
        {
            return false;
        }

        if (
            x >= region_.width
            || y >= region_.height
        )
        {
            return false;
        }


        const descriptor =
            planes_[band];

        /*
         * A non-empty certified writable view originated from an ordinarily
         * validated backing, so its reachable plane base is non-null.
         *
         * Keep the defensive check because WritableRasterView.init and
         * package-internal misuse must not cause an immediate null write.
         */
        if (descriptor.base is null)
        {
            return false;
        }


        const descriptorX =
            region_.x + x;

        const descriptorY =
            region_.y + y;

        const signedX =
            cast(ptrdiff_t) descriptorX;

        const signedY =
            cast(ptrdiff_t) descriptorY;

        const offset =
              signedY * descriptor.rowStrideElements
            + signedX * descriptor.sampleStrideElements;

        auto base =
            cast(T*) descriptor.base;

        *(base + offset) =
            value;

        return true;
    }
}


/++
    Constructs a WritableRasterView from metadata whose complete represented
    sample set has already been certified writable.

    This function performs no ResourceAccess or physical-range proof itself.

    Its caller must have established:

    - ordinary RasterView backing invariants;
    - complete write-capable resource coverage for every represented
      non-empty plane;
    - lifetime of descriptor metadata and physical storage.

    Child ROI construction may call this boundary without repeating physical
    certification because the child reachable sample set is a subset of the
    certified parent set.

    `return scope` ties the descriptor borrow in the returned view to the
    supplied stable descriptor block.
+/
private
WritableRasterView!T makeWritableRasterViewAssumeCertified(T)(
    return scope const(PlaneDescriptor)[] planes,
    Region2D region
)
@trusted
pure
nothrow
@nogc
{
    WritableRasterView!T result;

    result.planes_ =
        planes;

    result.region_ =
        region;

    return result;
}


/++
    Attempts to create a semantic WritableRasterView from complete physical
    raster metadata.

    This is the package-visible initial writable-capability boundary.

    It deliberately requires:

        retained ResourceEntry[]
        stable PlaneDescriptor[]
        Region2D

    and performs:

        ordinary backing validation
            ->
        writable resource certification
            ->
        private assume-certified construction

    A caller therefore cannot manufacture write capability from
    PlaneDescriptor[] + Region2D alone.

    `validation` always receives the ordinary backing-validation result.

    `certification` remains conservatively unsuccessful when ordinary
    validation fails.

    The returned borrow is lifetime-related to both resource metadata and
    descriptor metadata through the return-scope parameters.

    Success establishes only permission to write represented samples.

    It does not establish uniqueness, noalias, source/target non-overlap,
    execution layout or thread exclusivity.
+/
package(imagery.raster)
WritableRasterView!T tryMakeWritableRasterView(T)(
    return scope const(ResourceEntry)[] resources,
    return scope const(PlaneDescriptor)[] planes,
    Region2D region,
    out BackingValidationResult validation,
    out WritableBackingCertificationResult certification
)
@safe
nothrow
@nogc
{
    validation =
        validateRasterBackingLayout!T(
            resources,
            planes,
            region
        );

    certification =
        WritableBackingCertificationResult.init;


    if (!validation.ok)
    {
        return WritableRasterView!T.init;
    }


    certification =
        certifyWritableRasterBacking!T(
            resources,
            planes,
            region
        );


    if (!certification.ok)
    {
        return WritableRasterView!T.init;
    }


    return makeWritableRasterViewAssumeCertified!T(
        planes,
        region
    );
}


version (unittest)
{

import imagery.raster.resource :
    ResourceAccess;


unittest
{
    /*
     * Full read-write physical coverage may publish the semantic capability.
     */
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

    auto view =
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
    assert(view.planeCount == 1);

    assert(
        view.trySetSample(
            0,
            3,
            2,
            91
        )
    );

    assert(samples[11] == 91);
}


unittest
{
    /*
     * Ordinary backing validity alone is insufficient.
     *
     * A read-only resource produces no writable semantic capability.
     */
    ubyte[4] samples;

    const ResourceEntry[1] resources =
    [
        ResourceEntry(
            samples.ptr,
            samples.length,
            null,
            null,
            ResourceAccess.readOnly
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
    assert(!certification.ok);

    assert(view.planeCount == 0);
    assert(view.empty);
}


unittest
{
    ubyte[12] samples;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(view.planeCount == 1);
    assert(view.region == Region2D(0, 0, 4, 3));
    assert(view.width == 4);
    assert(view.height == 3);
    assert(!view.empty);

    assert(
        view.trySetSample(
            0,
            2,
            1,
            77
        )
    );

    assert(samples[6] == 77);

    ubyte value;

    assert(
        view.trySample(
            0,
            2,
            1,
            value
        )
    );

    assert(value == 77);
}


unittest
{
    /*
     * Invalid coordinates or plane index perform no write.
     */
    ubyte[4] samples =
        [1, 2, 3, 4];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    assert(
        !view.trySetSample(
            1,
            0,
            0,
            99
        )
    );

    assert(
        !view.trySetSample(
            0,
            4,
            0,
            99
        )
    );

    assert(
        !view.trySetSample(
            0,
            0,
            1,
            99
        )
    );

    assert(samples == [1, 2, 3, 4]);
}


unittest
{
    /*
     * A writable ROI inherits the already-established capability.
     */
    ubyte[12] samples;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr,
            4,
            1
        )
    ];

    auto parent =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    bool success;

    auto child =
        parent.tryRoi(
            Region2D(
                1,
                1,
                2,
                2
            ),
            success
        );

    assert(success);
    assert(child.region == Region2D(1, 1, 2, 2));

    assert(
        child.trySetSample(
            0,
            0,
            0,
            101
        )
    );

    assert(samples[5] == 101);

    ubyte value;

    assert(
        parent.trySample(
            0,
            1,
            1,
            value
        )
    );

    assert(value == 101);
}


unittest
{
    /*
     * Signed row strides preserve writable semantics.
     *
     * Logical row zero begins at the final physical row.
     */
    ubyte[12] samples;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 8,
            -4,
            1
        )
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(
        view.trySetSample(
            0,
            1,
            2,
            123
        )
    );

    /*
     * base = physical index 8
     * y=2 -> -8
     * x=1 -> +1
     * final physical index = 1
     */
    assert(samples[1] == 123);

    ubyte value;

    assert(
        view.trySample(
            0,
            1,
            2,
            value
        )
    );

    assert(value == 123);
}


unittest
{
    /*
     * Signed sample strides are independently writable.
     */
    ubyte[12] samples;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            samples.ptr + 3,
            4,
            -1
        )
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                3
            )
        );

    assert(
        view.trySetSample(
            0,
            2,
            1,
            211
        )
    );

    /*
     * base = physical index 3
     * y=1 -> +4
     * x=2 -> -2
     * final physical index = 5
     */
    assert(samples[5] == 211);

    ubyte value;

    assert(
        view.trySample(
            0,
            2,
            1,
            value
        )
    );

    assert(value == 211);
}


unittest
{
    /*
     * Multi-plane writes preserve logical plane selection.
     */
    ubyte[4] first;
    ubyte[4] second;

    const PlaneDescriptor[2] descriptors =
    [
        PlaneDescriptor(
            first.ptr,
            4,
            1
        ),

        PlaneDescriptor(
            second.ptr,
            4,
            1
        )
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    assert(view.planeCount == 2);

    assert(
        view.trySetSample(
            1,
            3,
            0,
            88
        )
    );

    assert(first[3] == 0);
    assert(second[3] == 88);
}


unittest
{
    /*
     * Empty views contain no writable sample.
     */
    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor.init
    ];

    auto view =
        makeWritableRasterViewAssumeCertified!ubyte(
            descriptors[],
            Region2D(
                10,
                20,
                0,
                0
            )
        );

    assert(view.empty);

    assert(
        !view.trySetSample(
            0,
            0,
            0,
            1
        )
    );

    ubyte value = 99;

    assert(
        !view.trySample(
            0,
            0,
            0,
            value
        )
    );

    assert(value == ubyte.init);
}


} // version (unittest)
