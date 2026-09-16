module app;

import std.math : isClose;
import std.stdio : writefln, writeln;

import views :
    AffineRGBView,
    PlaneDescriptor,
    MultiPlaneRasterView,
    rgbToGrayAffine,
    rgbToGrayPlanes,
    rgbToGrayAffineInterleaved3,
    rgbToGrayPlanesInterleaved3,
    rgbToGrayPlanesPlanar1;


enum size_t WIDTH = 64;
enum size_t HEIGHT = 32;
enum size_t PIXELS = WIDTH * HEIGHT;


void fillRGB(
    float[] interleaved,
    float[] red,
    float[] green,
    float[] blue
)
{
    foreach (i; 0 .. PIXELS)
    {
        const r = cast(float)((i * 17 + 3) & 1023) / 1023.0f;
        const g = cast(float)((i * 29 + 7) & 1023) / 1023.0f;
        const b = cast(float)((i * 43 + 11) & 1023) / 1023.0f;

        interleaved[i * 3 + 0] = r;
        interleaved[i * 3 + 1] = g;
        interleaved[i * 3 + 2] = b;

        red[i] = r;
        green[i] = g;
        blue[i] = b;
    }
}


void compareOutputs(
    const(float)[] a,
    const(float)[] b
)
{
    assert(a.length == b.length);

    foreach (i; 0 .. a.length)
    {
        assert(
            isClose(a[i], b[i]),
            "grayscale output mismatch"
        );
    }
}


void main()
{
    auto interleaved = new float[PIXELS * 3];

    auto red = new float[PIXELS];
    auto green = new float[PIXELS];
    auto blue = new float[PIXELS];

    auto grayAffine = new float[PIXELS];
    auto grayInterleavedPlanes = new float[PIXELS];
    auto grayPlanarPlanes = new float[PIXELS];

    auto grayAffineStatic = new float[PIXELS];
    auto grayInterleavedPlanesStatic = new float[PIXELS];
    auto grayPlanarPlanesStatic = new float[PIXELS];

    fillRGB(
        interleaved,
        red,
        green,
        blue
    );


    // --------------------------------------------------------
    // Candidate A: one affine interleaved allocation
    // --------------------------------------------------------

    auto affine =
        AffineRGBView!float(
            interleaved.ptr,
            WIDTH,
            HEIGHT,
            WIDTH * 3,
            3,
            1,
            0,
            0
        );


    // --------------------------------------------------------
    // Candidate D: same interleaved allocation represented as
    // three logical scalar planes.
    // --------------------------------------------------------

    PlaneDescriptor!float[3] interleavedDescriptors = [
        PlaneDescriptor!float(interleaved.ptr + 0, WIDTH * 3, 3),
        PlaneDescriptor!float(interleaved.ptr + 1, WIDTH * 3, 3),
        PlaneDescriptor!float(interleaved.ptr + 2, WIDTH * 3, 3)
    ];

    auto interleavedPlanes =
        MultiPlaneRasterView!float(
            interleavedDescriptors[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    // --------------------------------------------------------
    // Candidate D: three completely separate allocations.
    // --------------------------------------------------------

    PlaneDescriptor!float[3] planarDescriptors = [
        PlaneDescriptor!float(red.ptr, WIDTH, 1),
        PlaneDescriptor!float(green.ptr, WIDTH, 1),
        PlaneDescriptor!float(blue.ptr, WIDTH, 1)
    ];

    auto planarPlanes =
        MultiPlaneRasterView!float(
            planarDescriptors[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    // --------------------------------------------------------
    // Correctness
    // --------------------------------------------------------

    const checksumAffine =
        rgbToGrayAffine(
            affine,
            grayAffine
        );

    const checksumInterleavedPlanes =
        rgbToGrayPlanes(
            interleavedPlanes,
            grayInterleavedPlanes
        );

    const checksumPlanarPlanes =
        rgbToGrayPlanes(
            planarPlanes,
            grayPlanarPlanes
        );

    compareOutputs(
        grayAffine,
        grayInterleavedPlanes
    );

    compareOutputs(
        grayAffine,
        grayPlanarPlanes
    );

    writeln("correctness: PASS");


    const checksumAffineStatic =
        rgbToGrayAffineInterleaved3(
            affine,
            grayAffineStatic
        );

    const checksumInterleavedPlanesStatic =
        rgbToGrayPlanesInterleaved3(
            interleavedPlanes,
            grayInterleavedPlanesStatic
        );

    const checksumPlanarPlanesStatic =
        rgbToGrayPlanesPlanar1(
            planarPlanes,
            grayPlanarPlanesStatic
        );

    compareOutputs(
        grayAffine,
        grayAffineStatic
    );

    compareOutputs(
        grayAffine,
        grayInterleavedPlanesStatic
    );

    compareOutputs(
        grayAffine,
        grayPlanarPlanesStatic
    );

    writeln("specialized correctness: PASS");

    assert(isClose(checksumAffine, checksumAffineStatic));
    assert(isClose(checksumAffine, checksumInterleavedPlanesStatic));
    assert(isClose(checksumAffine, checksumPlanarPlanesStatic));



    // --------------------------------------------------------
    // O(1) ROI semantics
    // --------------------------------------------------------

    const affineRoi =
        affine.roi(
            7,
            5,
            23,
            11
        );

    const planeRoi =
        interleavedPlanes.roi(
            7,
            5,
            23,
            11
        );

    assert(affineRoi.originX == 7);
    assert(affineRoi.originY == 5);
    assert(affineRoi.width == 23);
    assert(affineRoi.height == 11);

    assert(planeRoi.originX == 7);
    assert(planeRoi.originY == 5);
    assert(planeRoi.width == 23);
    assert(planeRoi.height == 11);

    /*
     * The descriptor storage is reused unchanged by the ROI.
     */
    assert(
        planeRoi.planes.ptr
        is
        interleavedPlanes.planes.ptr
    );

    writeln("ROI descriptor reuse: PASS");


    // --------------------------------------------------------
    // Metadata sizes
    // --------------------------------------------------------

    writefln(
        "sizeof(AffineRGBView!float)       = %s bytes",
        AffineRGBView!float.sizeof
    );

    writefln(
        "sizeof(PlaneDescriptor!float)     = %s bytes",
        PlaneDescriptor!float.sizeof
    );

    writefln(
        "sizeof(MultiPlaneRasterView!float)= %s bytes",
        MultiPlaneRasterView!float.sizeof
    );

    writefln(
        "3 PlaneDescriptor metadata        = %s bytes",
        3 * PlaneDescriptor!float.sizeof
    );


    // Prevent whole-program elimination in aggressive builds.
    writefln(
        "checksums: %.9f %.9f %.9f",
        checksumAffine,
        checksumInterleavedPlanes,
        checksumPlanarPlanes
    );
}
