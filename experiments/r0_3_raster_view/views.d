module views;

/*
 * Candidate A
 * -----------
 *
 * One affine base allocation.
 *
 * Compact and expressive for interleaved RGB and for some layouts contained
 * in one allocation, but it cannot generally represent independently
 * allocated planes.
 */
struct AffineRGBView(T)
{
    T* base;

    size_t width;
    size_t height;

    ptrdiff_t rowStride;
    ptrdiff_t pixelStride;
    ptrdiff_t channelStride;

    size_t originX;
    size_t originY;

    AffineRGBView roi(
        size_t x,
        size_t y,
        size_t roiWidth,
        size_t roiHeight
    ) nothrow @nogc
    {
        assert(x <= width);
        assert(y <= height);
        assert(roiWidth <= width - x);
        assert(roiHeight <= height - y);

        auto result = this;

        result.originX += x;
        result.originY += y;
        result.width = roiWidth;
        result.height = roiHeight;

        return result;
    }
}


/*
 * Candidate D-like descriptor
 * ---------------------------
 *
 * One logical scalar band.
 *
 * `base` may belong to the same allocation as another plane or to a
 * completely separate allocation.
 */
struct PlaneDescriptor(T)
{
    T* base;

    ptrdiff_t rowStride;
    ptrdiff_t sampleStride;
}


/*
 * Candidate D
 * -----------
 *
 * Stable plane descriptors plus region geometry.
 *
 * ROI construction changes only geometry. It does not rewrite or allocate
 * one descriptor per plane.
 */
struct MultiPlaneRasterView(T)
{
    PlaneDescriptor!T[] planes;

    size_t width;
    size_t height;

    size_t originX;
    size_t originY;

    @property
    size_t planeCount() const nothrow @nogc
    {
        return planes.length;
    }

    MultiPlaneRasterView roi(
        size_t x,
        size_t y,
        size_t roiWidth,
        size_t roiHeight
    ) nothrow @nogc
    {
        assert(x <= width);
        assert(y <= height);
        assert(roiWidth <= width - x);
        assert(roiHeight <= height - y);

        auto result = this;

        result.originX += x;
        result.originY += y;
        result.width = roiWidth;
        result.height = roiHeight;

        /*
         * `planes` is only a copied slice descriptor.
         *
         * No plane-descriptor allocation or rewriting occurs.
         */
        return result;
    }
}


/*
 * Candidate A kernel.
 *
 * Deliberately written in the natural affine/interleaved form so LLVM can
 * see one regular RGB pixel stream.
 */
pragma(inline, false)
float rgbToGrayAffine(
    AffineRGBView!float view,
    float[] gray
)
{
    assert(gray.length >= view.width * view.height);

    size_t outIndex;

    foreach (y; 0 .. view.height)
    {
        auto pixel =
            view.base
            + cast(ptrdiff_t)(view.originY + y) * view.rowStride
            + cast(ptrdiff_t)view.originX * view.pixelStride;

        foreach (x; 0 .. view.width)
        {
            const r = pixel[0 * view.channelStride];
            const g = pixel[1 * view.channelStride];
            const b = pixel[2 * view.channelStride];

            gray[outIndex++] =
                  0.2126f * r
                + 0.7152f * g
                + 0.0722f * b;

            pixel += view.pixelStride;
        }
    }

    return gray[0] + gray[view.width * view.height - 1];
}


/*
 * Candidate D kernel.
 *
 * The descriptors are loaded once before the hot loop.
 *
 * For interleaved RGB this means three logical band streams with
 * sampleStride=3.
 *
 * For planar RGB the same kernel receives three streams with sampleStride=1.
 */
pragma(inline, false)
float rgbToGrayPlanes(
    MultiPlaneRasterView!float view,
    float[] gray
)
{
    assert(view.planes.length >= 3);
    assert(gray.length >= view.width * view.height);

    auto red = view.planes[0];
    auto green = view.planes[1];
    auto blue = view.planes[2];

    size_t outIndex;

    foreach (y; 0 .. view.height)
    {
        auto r =
            red.base
            + cast(ptrdiff_t)(view.originY + y) * red.rowStride
            + cast(ptrdiff_t)view.originX * red.sampleStride;

        auto g =
            green.base
            + cast(ptrdiff_t)(view.originY + y) * green.rowStride
            + cast(ptrdiff_t)view.originX * green.sampleStride;

        auto b =
            blue.base
            + cast(ptrdiff_t)(view.originY + y) * blue.rowStride
            + cast(ptrdiff_t)view.originX * blue.sampleStride;

        foreach (x; 0 .. view.width)
        {
            gray[outIndex++] =
                  0.2126f * *r
                + 0.7152f * *g
                + 0.0722f * *b;

            r += red.sampleStride;
            g += green.sampleStride;
            b += blue.sampleStride;
        }
    }

    return gray[0] + gray[view.width * view.height - 1];
}

// R0.3 EXPERIMENT 2: STATIC LAYOUT EXECUTION
//
// Keep the semantic view representations unchanged, but make the hot-loop
// sample layout known to the compiler.
//
// This separates two questions:
//
//   1. does the representation itself inhibit optimisation?
//   2. or does the fully runtime-variable stride inhibit optimisation?


/*
 * Candidate A, specialized execution for tightly interleaved RGB.
 *
 * The view still carries runtime pixel/channel strides because that is part
 * of Candidate A's representation, but this execution path has already
 * classified the layout as:
 *
 *     pixelStride   = 3
 *     channelStride = 1
 */
pragma(inline, false)
float rgbToGrayAffineInterleaved3(
    AffineRGBView!float view,
    float[] gray
)
{
    assert(view.pixelStride == 3);
    assert(view.channelStride == 1);
    assert(gray.length >= view.width * view.height);

    size_t outIndex;

    foreach (y; 0 .. view.height)
    {
        auto pixel =
            view.base
            + cast(ptrdiff_t)(view.originY + y) * view.rowStride
            + cast(ptrdiff_t)view.originX * 3;

        foreach (x; 0 .. view.width)
        {
            const r = pixel[0];
            const g = pixel[1];
            const b = pixel[2];

            gray[outIndex++] =
                  0.2126f * r
                + 0.7152f * g
                + 0.0722f * b;

            pixel += 3;
        }
    }

    return gray[0] + gray[view.width * view.height - 1];
}


/*
 * Candidate D, specialized execution for interleaved RGB.
 *
 * Plane descriptors remain the semantic representation.  Only the execution
 * path knows that all three logical bands advance by exactly three floats.
 */
pragma(inline, false)
float rgbToGrayPlanesInterleaved3(
    MultiPlaneRasterView!float view,
    float[] gray
)
{
    assert(view.planes.length >= 3);
    assert(gray.length >= view.width * view.height);

    auto red = view.planes[0];
    auto green = view.planes[1];
    auto blue = view.planes[2];

    assert(red.sampleStride == 3);
    assert(green.sampleStride == 3);
    assert(blue.sampleStride == 3);

    size_t outIndex;

    foreach (y; 0 .. view.height)
    {
        auto r =
            red.base
            + cast(ptrdiff_t)(view.originY + y) * red.rowStride
            + cast(ptrdiff_t)view.originX * 3;

        auto g =
            green.base
            + cast(ptrdiff_t)(view.originY + y) * green.rowStride
            + cast(ptrdiff_t)view.originX * 3;

        auto b =
            blue.base
            + cast(ptrdiff_t)(view.originY + y) * blue.rowStride
            + cast(ptrdiff_t)view.originX * 3;

        foreach (x; 0 .. view.width)
        {
            gray[outIndex++] =
                  0.2126f * *r
                + 0.7152f * *g
                + 0.0722f * *b;

            r += 3;
            g += 3;
            b += 3;
        }
    }

    return gray[0] + gray[view.width * view.height - 1];
}


/*
 * Candidate D, specialized execution for planar contiguous samples.
 *
 * Each band may still have an independent base allocation and independent
 * row stride.  Only the within-row sample stride is known to be one.
 */
pragma(inline, false)
float rgbToGrayPlanesPlanar1(
    MultiPlaneRasterView!float view,
    float[] gray
)
{
    assert(view.planes.length >= 3);
    assert(gray.length >= view.width * view.height);

    auto red = view.planes[0];
    auto green = view.planes[1];
    auto blue = view.planes[2];

    assert(red.sampleStride == 1);
    assert(green.sampleStride == 1);
    assert(blue.sampleStride == 1);

    size_t outIndex;

    foreach (y; 0 .. view.height)
    {
        auto r =
            red.base
            + cast(ptrdiff_t)(view.originY + y) * red.rowStride
            + cast(ptrdiff_t)view.originX;

        auto g =
            green.base
            + cast(ptrdiff_t)(view.originY + y) * green.rowStride
            + cast(ptrdiff_t)view.originX;

        auto b =
            blue.base
            + cast(ptrdiff_t)(view.originY + y) * blue.rowStride
            + cast(ptrdiff_t)view.originX;

        foreach (x; 0 .. view.width)
        {
            gray[outIndex++] =
                  0.2126f * *r
                + 0.7152f * *g
                + 0.0722f * *b;

            ++r;
            ++g;
            ++b;
        }
    }

    return gray[0] + gray[view.width * view.height - 1];
}
