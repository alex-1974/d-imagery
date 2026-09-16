/++
    Non-owning read-only semantic raster view.

    RasterView separates:

    - resident region geometry;
    - physical plane description;
    - storage ownership;
    - execution representation.

    A RasterView owns neither pixel storage nor PlaneDescriptor storage.

    Construction from physical metadata is deliberately restricted to the
    imagery.raster package. The caller of that trusted boundary must already
    have validated storage reachability, alignment, stride arithmetic, sample
    type interpretation, and lifetime.
+/
module imagery.raster.view;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.sample :
    isRasterSampleType;


/++
    Read-only non-owning raster view.

    Plane order is logical band order.

    The region coordinates belong to the resident coordinate system defined
    by the stable plane descriptors.

    They are not global LogicalImage coordinates.

    PlaneDescriptor.base represents resident descriptor coordinate `(0, 0)`.
+/
struct RasterView(T)
{
    static assert(
        isRasterSampleType!T,
        "RasterView sample type must be an unqualified POD value type "
        ~ "without indirections."
    );

private:
    const(PlaneDescriptor)[] planes_;

    Region2D region_;

public:

    /++
        Number of logical planes/bands.
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
        Resident width of this view.
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
        Resident height of this view.
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
        Whether this view has zero resident area.
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
        Attempts to create a child region relative to this view.

        `relative.x` and `relative.y` are relative to the current view origin.

        On success the returned RasterView:

        - reuses the exact same stable descriptor block;
        - owns no new storage;
        - contains the resolved Region2D in the same resident descriptor
          coordinate system;
        - remains lifetime-bound to this view.

        On failure `success` is false and RasterView.init is returned.

        Empty child regions are valid when they are geometrically contained
        within the parent region.
    +/
    RasterView!T tryRoi(
        Region2D relative,
        out bool success
    ) const
    return scope
    @safe
    pure
    nothrow
    @nogc
    {
        success = false;

        Region2D resolved;

        if (!region_.tryResolveRelative(
            relative,
            resolved
        ))
        {
            return RasterView!T.init;
        }

        success = true;

        return makeRasterViewAssumeValidated!T(
            planes_,
            resolved
        );
    }


    /++
        Attempts to read one logical sample.

        Coordinates `x` and `y` are relative to this view.

        Internally they resolve into resident descriptor-space coordinates.
        They are never interpreted as global LogicalImage coordinates.

        Returns false when the band or coordinates are outside the view.

        On failure `value` is reset to T.init.

        This accessor returns a value copy and therefore grants no write
        capability to the underlying raster storage.

        This is primarily a correctness/control-plane accessor. Performance
        kernels will later use separately validated internal adapters rather
        than repeatedly performing these bounds checks.
    +/
    bool trySample(
        size_t band,
        size_t x,
        size_t y,
        out T value
    ) const
    @trusted
    nothrow
    @nogc
    {
        value = T.init;

        if (band >= planes_.length)
        {
            return false;
        }

        if (x >= region_.width || y >= region_.height)
        {
            return false;
        }

        const descriptor =
            planes_[band];

        if (descriptor.base is null)
        {
            return false;
        }

        /*
         * The following arithmetic is permitted only because construction of
         * a RasterView is restricted to the validated package boundary.
         *
         * That boundary must prove that:
         *
         * - resident descriptor coordinates are representable;
         * - conversion to ptrdiff_t is representable;
         * - both stride products are representable;
         * - their sum is representable;
         * - the resulting address remains inside retained storage;
         * - negative strides remain inside retained storage.
         */

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

        const base =
            cast(const(T)*) descriptor.base;

        value =
            *(base + offset);

        return true;
    }
}


/++
    Internal construction boundary for an already validated RasterView.

    This function does not itself prove resource bounds. Its caller must have
    established all RasterView invariants before calling it.

    The function is package-visible rather than part of the public raster API.

    `return scope` ties aliases in the resulting view to the supplied stable
    descriptor block.
+/
package(imagery.raster)
RasterView!T makeRasterViewAssumeValidated(T)(
    return scope const(PlaneDescriptor)[] planes,
    Region2D region
)
@trusted
pure
nothrow
@nogc
{
    RasterView!T result;

    result.planes_ = planes;
    result.region_ = region;

    return result;
}


version (unittest)
{

import imagery.raster.internal.test_data :
    interleaved3Band4x3,
    logicalSample,
    planar3Band4x3,
    roiBand0_x1_y1_w2_h2,
    singleBand4x3,
    testBands,
    testHeight,
    testWidth;


/++
    Build canonical planar descriptors.

    Each logical plane has its own contiguous 4 x 3 region inside the fixture.
+/
private
RasterView!ubyte makePlanarTestView()
@trusted
nothrow
@nogc
{
    enum size_t planeSamples =
        testWidth * testHeight;

    static const PlaneDescriptor[3] descriptors =
    [
        PlaneDescriptor(
            cast(const(void)*)(
                planar3Band4x3.ptr
                + 0 * planeSamples
            ),
            cast(ptrdiff_t) testWidth,
            1
        ),

        PlaneDescriptor(
            cast(const(void)*)(
                planar3Band4x3.ptr
                + 1 * planeSamples
            ),
            cast(ptrdiff_t) testWidth,
            1
        ),

        PlaneDescriptor(
            cast(const(void)*)(
                planar3Band4x3.ptr
                + 2 * planeSamples
            ),
            cast(ptrdiff_t) testWidth,
            1
        )
    ];

    return makeRasterViewAssumeValidated!ubyte(
        descriptors[],
        Region2D(
            0,
            0,
            testWidth,
            testHeight
        )
    );
}


/++
    Build canonical pixel-interleaved descriptors.

    All three logical bands refer to the same physical pixel stream.

    rowStride    = width * bandCount
    sampleStride = bandCount
+/
private
RasterView!ubyte makeInterleavedTestView()
@trusted
nothrow
@nogc
{
    static const PlaneDescriptor[3] descriptors =
    [
        PlaneDescriptor(
            cast(const(void)*)(
                interleaved3Band4x3.ptr + 0
            ),
            cast(ptrdiff_t)(
                testWidth * testBands
            ),
            cast(ptrdiff_t) testBands
        ),

        PlaneDescriptor(
            cast(const(void)*)(
                interleaved3Band4x3.ptr + 1
            ),
            cast(ptrdiff_t)(
                testWidth * testBands
            ),
            cast(ptrdiff_t) testBands
        ),

        PlaneDescriptor(
            cast(const(void)*)(
                interleaved3Band4x3.ptr + 2
            ),
            cast(ptrdiff_t)(
                testWidth * testBands
            ),
            cast(ptrdiff_t) testBands
        )
    ];

    return makeRasterViewAssumeValidated!ubyte(
        descriptors[],
        Region2D(
            0,
            0,
            testWidth,
            testHeight
        )
    );
}


unittest
{
    auto planar =
        makePlanarTestView();

    auto interleaved =
        makeInterleavedTestView();

    assert(planar.planeCount == testBands);
    assert(interleaved.planeCount == testBands);

    assert(planar.width == testWidth);
    assert(planar.height == testHeight);

    assert(interleaved.width == testWidth);
    assert(interleaved.height == testHeight);

    assert(!planar.empty);
    assert(!interleaved.empty);


    foreach (band; 0 .. testBands)
    {
        foreach (y; 0 .. testHeight)
        {
            foreach (x; 0 .. testWidth)
            {
                ubyte planarValue;
                ubyte interleavedValue;

                assert(
                    planar.trySample(
                        band,
                        x,
                        y,
                        planarValue
                    )
                );

                assert(
                    interleaved.trySample(
                        band,
                        x,
                        y,
                        interleavedValue
                    )
                );

                const expected =
                    logicalSample(
                        band,
                        x,
                        y
                    );

                assert(planarValue == expected);
                assert(interleavedValue == expected);

                /*
                 * Central semantic invariant:
                 *
                 * physical layout must not change the logical sample value.
                 */
                assert(
                    planarValue
                    == interleavedValue
                );
            }
        }
    }
}


unittest
{
    auto planar =
        makePlanarTestView();

    auto interleaved =
        makeInterleavedTestView();

    ubyte planarValue;
    ubyte interleavedValue;

    /*
     * Explicit diagnostic sample discussed during design:
     *
     *     band = 1
     *     x    = 2
     *     y    = 1
     *
     * expected = 100 + 10 + 2 = 112
     */

    assert(
        planar.trySample(
            1,
            2,
            1,
            planarValue
        )
    );

    assert(
        interleaved.trySample(
            1,
            2,
            1,
            interleavedValue
        )
    );

    assert(planarValue == 112);
    assert(interleavedValue == 112);
}


unittest
{
    /*
     * A non-zero Region2D exercises logical-origin translation without yet
     * introducing the public ROI transformation API.
     */

    static const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            cast(const(void)*) singleBand4x3.ptr,
            cast(ptrdiff_t) testWidth,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                1,
                1,
                2,
                2
            )
        );

    assert(view.region == Region2D(1, 1, 2, 2));
    assert(view.width == 2);
    assert(view.height == 2);

    size_t i = 0;

    foreach (y; 0 .. view.height)
    {
        foreach (x; 0 .. view.width)
        {
            ubyte value;

            assert(
                view.trySample(
                    0,
                    x,
                    y,
                    value
                )
            );

            assert(
                value
                == roiBand0_x1_y1_w2_h2[i]
            );

            ++i;
        }
    }

    assert(
        i
        == roiBand0_x1_y1_w2_h2.length
    );
}


unittest
{
    /*
     * Signed row strides are part of the representation.
     *
     * Logical row 0 starts at physical row 2 and traversal then moves
     * backwards through memory.
     */

    static const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            cast(const(void)*)(
                singleBand4x3.ptr
                + 2 * testWidth
            ),
            -cast(ptrdiff_t) testWidth,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                testWidth,
                testHeight
            )
        );

    foreach (y; 0 .. testHeight)
    {
        foreach (x; 0 .. testWidth)
        {
            ubyte value;

            assert(
                view.trySample(
                    0,
                    x,
                    y,
                    value
                )
            );

            const expected =
                cast(ubyte)(
                    (testHeight - 1 - y) * 10
                    + x
                );

            assert(value == expected);
        }
    }
}


unittest
{
    /*
     * Signed sample strides are independently supported.
     *
     * Logical x=0 starts at the physical right edge of each row.
     */

    static const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            cast(const(void)*)(
                singleBand4x3.ptr
                + testWidth - 1
            ),
            cast(ptrdiff_t) testWidth,
            -1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!ubyte(
            descriptors[],
            Region2D(
                0,
                0,
                testWidth,
                testHeight
            )
        );

    foreach (y; 0 .. testHeight)
    {
        foreach (x; 0 .. testWidth)
        {
            ubyte value;

            assert(
                view.trySample(
                    0,
                    x,
                    y,
                    value
                )
            );

            const expected =
                cast(ubyte)(
                    y * 10
                    + testWidth - 1 - x
                );

            assert(value == expected);
        }
    }
}


unittest
{
    auto view =
        makePlanarTestView();

    ubyte value = 255;

    assert(
        !view.trySample(
            testBands,
            0,
            0,
            value
        )
    );

    assert(value == ubyte.init);

    value = 255;

    assert(
        !view.trySample(
            0,
            testWidth,
            0,
            value
        )
    );

    assert(value == ubyte.init);

    value = 255;

    assert(
        !view.trySample(
            0,
            0,
            testHeight,
            value
        )
    );

    assert(value == ubyte.init);
}


unittest
{
    RasterView!ubyte emptyView;

    assert(emptyView.planeCount == 0);
    assert(emptyView.width == 0);
    assert(emptyView.height == 0);
    assert(emptyView.empty);

    ubyte value = 255;

    assert(
        !emptyView.trySample(
            0,
            0,
            0,
            value
        )
    );

    assert(value == ubyte.init);
}


unittest
{
    /*
     * Basic ROI:
     *
     * parent:
     *
     *      0  1  2  3
     *     10 11 12 13
     *     20 21 22 23
     *
     * relative ROI (1, 1, 2, 2):
     *
     *     11 12
     *     21 22
     */

    auto parent =
        makePlanarTestView();

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

    assert(
        child.region
        == Region2D(
            1,
            1,
            2,
            2
        )
    );

    assert(child.width == 2);
    assert(child.height == 2);

    /*
     * ROI must reuse, not reconstruct, the descriptor block.
     */
    assert(
        child.planes_.ptr
        is parent.planes_.ptr
    );

    assert(
        child.planes_.length
        == parent.planes_.length
    );


    foreach (band; 0 .. testBands)
    {
        foreach (y; 0 .. child.height)
        {
            foreach (x; 0 .. child.width)
            {
                ubyte value;

                assert(
                    child.trySample(
                        band,
                        x,
                        y,
                        value
                    )
                );

                assert(
                    value
                    == logicalSample(
                        band,
                        x + 1,
                        y + 1
                    )
                );
            }
        }
    }
}


unittest
{
    /*
     * Repeated ROI transformations accumulate logical origin while retaining
     * the exact same descriptor block.
     */

    auto root =
        makeInterleavedTestView();

    bool firstSuccess;

    auto first =
        root.tryRoi(
            Region2D(
                1,
                0,
                3,
                3
            ),
            firstSuccess
        );

    assert(firstSuccess);

    bool secondSuccess;

    auto second =
        first.tryRoi(
            Region2D(
                1,
                1,
                2,
                2
            ),
            secondSuccess
        );

    assert(secondSuccess);

    assert(
        first.region
        == Region2D(
            1,
            0,
            3,
            3
        )
    );

    assert(
        second.region
        == Region2D(
            2,
            1,
            2,
            2
        )
    );

    assert(
        first.planes_.ptr
        is root.planes_.ptr
    );

    assert(
        second.planes_.ptr
        is root.planes_.ptr
    );


    ubyte topLeft;
    ubyte bottomRight;

    assert(
        second.trySample(
            2,
            0,
            0,
            topLeft
        )
    );

    assert(
        second.trySample(
            2,
            1,
            1,
            bottomRight
        )
    );

    assert(topLeft == 212);
    assert(bottomRight == 223);
}


unittest
{
    /*
     * A geometrically invalid child must be rejected without producing a
     * partially valid view.
     */

    auto parent =
        makePlanarTestView();

    bool success = true;

    auto invalid =
        parent.tryRoi(
            Region2D(
                3,
                2,
                2,
                2
            ),
            success
        );

    assert(!success);

    assert(invalid.planeCount == 0);
    assert(invalid.region == Region2D.init);
    assert(invalid.empty);


    success = true;

    auto farOutside =
        parent.tryRoi(
            Region2D(
                size_t.max,
                0,
                1,
                1
            ),
            success
        );

    assert(!success);

    assert(farOutside.planeCount == 0);
    assert(farOutside.region == Region2D.init);
}


unittest
{
    /*
     * Empty regions are valid.

     * The bottom-right boundary is one-past the final sample in both axes,
     * but no pointer is formed or dereferenced because the child has zero
     * logical area.
     */

    auto parent =
        makePlanarTestView();

    bool success;

    auto emptyChild =
        parent.tryRoi(
            Region2D(
                testWidth,
                testHeight,
                0,
                0
            ),
            success
        );

    assert(success);

    assert(emptyChild.empty);

    assert(
        emptyChild.region
        == Region2D(
            testWidth,
            testHeight,
            0,
            0
        )
    );

    assert(
        emptyChild.planes_.ptr
        is parent.planes_.ptr
    );

    ubyte value = 255;

    assert(
        !emptyChild.trySample(
            0,
            0,
            0,
            value
        )
    );

    assert(value == ubyte.init);
}


} // version (unittest)
