module mir_probe;

import std.stdio : writeln;

import mir.ndslice :
    Slice,
    Universal,
    Canonical,
    Contiguous;

import views :
    PlaneDescriptor,
    MultiPlaneRasterView;

import mir_adapter :
    MirUniversalPlane,
    MirCanonicalPlane,
    MirContiguousPlane,
    asMirUniversal,
    asMirCanonical,
    asMirContiguous,
    canAdaptCanonical,
    canAdaptContiguous,
    canAdaptContiguousFlat;


void main()
{
    enum size_t WIDTH = 8;
    enum size_t HEIGHT = 4;


    /*
     * ------------------------------------------------------------
     * Interleaved RGB:
     *
     * each logical band has sampleStride == 3.
     * ------------------------------------------------------------
     */
    auto rgb =
        new float[WIDTH * HEIGHT * 3];

    foreach (y; 0 .. HEIGHT)
    {
        foreach (x; 0 .. WIDTH)
        {
            const i =
                (y * WIDTH + x) * 3;

            rgb[i + 0] =
                cast(float)(1000 + y * 100 + x * 10 + 1);

            rgb[i + 1] =
                cast(float)(1000 + y * 100 + x * 10 + 2);

            rgb[i + 2] =
                cast(float)(1000 + y * 100 + x * 10 + 3);
        }
    }


    PlaneDescriptor!float[3]
        rgbDescriptors =
    [
        PlaneDescriptor!float(
            rgb.ptr + 0,
            WIDTH * 3,
            3
        ),
        PlaneDescriptor!float(
            rgb.ptr + 1,
            WIDTH * 3,
            3
        ),
        PlaneDescriptor!float(
            rgb.ptr + 2,
            WIDTH * 3,
            3
        )
    ];


    auto rgbView =
        MultiPlaneRasterView!float(
            rgbDescriptors[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    auto rgbRoi =
        rgbView.roi(
            2,
            1,
            3,
            2
        );


    auto redUniversal =
        asMirUniversal(
            rgbRoi,
            0
        );

    static assert(
        is(
            typeof(redUniversal)
            ==
            MirUniversalPlane!float
        )
    );

    assert(redUniversal.length!0 == 2);
    assert(redUniversal.length!1 == 3);

    assert(redUniversal[0, 0] == 1121.0f);
    assert(redUniversal[0, 1] == 1131.0f);
    assert(redUniversal[1, 2] == 1241.0f);

    assert(!canAdaptCanonical(rgbRoi, 0));
    assert(!canAdaptContiguous(rgbRoi, 0));

    writeln(
        "Mir Universal interleaved ROI: PASS"
    );


    /*
     * ------------------------------------------------------------
     * Planar storage with padded rows.
     *
     * sampleStride == 1, rowStride > logical width.
     *
     * This is Canonical, but not fully Contiguous.
     * ------------------------------------------------------------
     */
    enum size_t PADDED_STRIDE = WIDTH + 3;

    auto padded =
        new float[HEIGHT * PADDED_STRIDE];

    foreach (y; 0 .. HEIGHT)
    {
        foreach (x; 0 .. WIDTH)
        {
            padded[y * PADDED_STRIDE + x] =
                cast(float)(2000 + y * 100 + x);
        }
    }


    PlaneDescriptor!float[1]
        paddedDescriptor =
    [
        PlaneDescriptor!float(
            padded.ptr,
            PADDED_STRIDE,
            1
        )
    ];


    auto paddedView =
        MultiPlaneRasterView!float(
            paddedDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    assert(canAdaptCanonical(paddedView, 0));
    assert(!canAdaptContiguous(paddedView, 0));


    auto paddedCanonical =
        asMirCanonical(
            paddedView,
            0
        );

    static assert(
        is(
            typeof(paddedCanonical)
            ==
            MirCanonicalPlane!float
        )
    );

    assert(paddedCanonical[0, 0] == 2000.0f);
    assert(paddedCanonical[1, 0] == 2100.0f);
    assert(paddedCanonical[3, 7] == 2307.0f);

    writeln(
        "Mir Canonical padded planar: PASS"
    );


    /*
     * ------------------------------------------------------------
     * Fully contiguous planar storage.
     * ------------------------------------------------------------
     */
    auto contiguous =
        new float[WIDTH * HEIGHT];

    foreach (i; 0 .. contiguous.length)
        contiguous[i] = cast(float)(3000 + i);


    PlaneDescriptor!float[1]
        contiguousDescriptor =
    [
        PlaneDescriptor!float(
            contiguous.ptr,
            WIDTH,
            1
        )
    ];


    auto contiguousView =
        MultiPlaneRasterView!float(
            contiguousDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    assert(canAdaptCanonical(contiguousView, 0));
    assert(canAdaptContiguous(contiguousView, 0));
    assert(canAdaptContiguousFlat(contiguousView, 0));


    auto contiguousMir =
        asMirContiguous(
            contiguousView,
            0
        );

    static assert(
        is(
            typeof(contiguousMir)
            ==
            MirContiguousPlane!float
        )
    );

    assert(contiguousMir[0, 0] == 3000.0f);
    assert(contiguousMir[3, 7] == 3031.0f);

    writeln(
        "Mir Contiguous full plane: PASS"
    );


    /*
     * Narrow ROI of the same physically contiguous image.
     *
     * It remains unit-stride in x, but rows are separated by WIDTH rather
     * than roi.width.  Therefore Canonical is valid, Contiguous is not.
     */
    auto narrowRoi =
        contiguousView.roi(
            2,
            1,
            3,
            2
        );

    assert(canAdaptCanonical(narrowRoi, 0));
    assert(!canAdaptContiguous(narrowRoi, 0));
    assert(!canAdaptContiguousFlat(narrowRoi, 0));

    auto narrowCanonical =
        asMirCanonical(
            narrowRoi,
            0
        );

    assert(narrowCanonical.length!0 == 2);
    assert(narrowCanonical.length!1 == 3);

    assert(narrowCanonical[0, 0] == 3010.0f);
    assert(narrowCanonical[0, 2] == 3012.0f);
    assert(narrowCanonical[1, 0] == 3018.0f);

    writeln(
        "Mir Canonical narrow ROI: PASS"
    );


    writeln(
        "R0.3 Mir adapter mapping probe: PASS"
    );
}
