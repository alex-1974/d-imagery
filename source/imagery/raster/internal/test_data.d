/++
    Canonical synthetic raster data used by d-imagery unit tests.

    This module exists only in unittest builds.

    Every logical sample is uniquely determined by:

        value = band * 100 + y * 10 + x

    This makes indexing, band-selection, ROI, stride, and layout errors
    immediately visible from the resulting value.
+/
module imagery.raster.internal.test_data;


version (unittest)
{


enum size_t testWidth = 4;
enum size_t testHeight = 3;
enum size_t testBands = 3;


/++
    Returns the canonical logical sample value for a coordinate.
+/
ubyte logicalSample(
    size_t band,
    size_t x,
    size_t y
)
@safe
pure
nothrow
@nogc
{
    return cast(ubyte)(
        band * 100
        + y * 10
        + x
    );
}


/++
    Offset of a logical sample in planar band-major storage.
+/
size_t planarOffset(
    size_t band,
    size_t x,
    size_t y
)
@safe
pure
nothrow
@nogc
{
    return band * testWidth * testHeight
        + y * testWidth
        + x;
}


/++
    Offset of a logical sample in pixel-interleaved storage.
+/
size_t interleavedOffset(
    size_t band,
    size_t x,
    size_t y
)
@safe
pure
nothrow
@nogc
{
    return (y * testWidth + x) * testBands
        + band;
}


/++
    One-band canonical 4 x 3 raster.

       0   1   2   3
      10  11  12  13
      20  21  22  23
+/
immutable ubyte[testWidth * testHeight] singleBand4x3 =
[
     0,  1,  2,  3,
    10, 11, 12, 13,
    20, 21, 22, 23
];


/++
    Three-band planar representation.

    Physical order:

        complete band 0
        complete band 1
        complete band 2
+/
immutable ubyte[
    testWidth * testHeight * testBands
] planar3Band4x3 =
[
      0,   1,   2,   3,
     10,  11,  12,  13,
     20,  21,  22,  23,

    100, 101, 102, 103,
    110, 111, 112, 113,
    120, 121, 122, 123,

    200, 201, 202, 203,
    210, 211, 212, 213,
    220, 221, 222, 223
];


/++
    Same logical three-band raster in pixel-interleaved representation.

    Physical order:

        pixel(0,0): band 0, band 1, band 2
        pixel(1,0): band 0, band 1, band 2
        ...
+/
immutable ubyte[
    testWidth * testHeight * testBands
] interleaved3Band4x3 =
[
      0, 100, 200,
      1, 101, 201,
      2, 102, 202,
      3, 103, 203,

     10, 110, 210,
     11, 111, 211,
     12, 112, 212,
     13, 113, 213,

     20, 120, 220,
     21, 121, 221,
     22, 122, 222,
     23, 123, 223
];


/++
    Expected band-0 values for ROI:

        x = 1
        y = 1
        width = 2
        height = 2

    Expected:

        11 12
        21 22
+/
immutable ubyte[4] roiBand0_x1_y1_w2_h2 =
[
    11, 12,
    21, 22
];


unittest
{
    foreach (y; 0 .. testHeight)
    {
        foreach (x; 0 .. testWidth)
        {
            const expected = logicalSample(
                0,
                x,
                y
            );

            const offset =
                y * testWidth + x;

            assert(
                singleBand4x3[offset]
                == expected
            );
        }
    }
}


unittest
{
    foreach (band; 0 .. testBands)
    {
        foreach (y; 0 .. testHeight)
        {
            foreach (x; 0 .. testWidth)
            {
                const expected =
                    logicalSample(
                        band,
                        x,
                        y
                    );

                assert(
                    planar3Band4x3[
                        planarOffset(
                            band,
                            x,
                            y
                        )
                    ]
                    == expected
                );

                assert(
                    interleaved3Band4x3[
                        interleavedOffset(
                            band,
                            x,
                            y
                        )
                    ]
                    == expected
                );
            }
        }
    }
}


unittest
{
    size_t i = 0;

    foreach (y; 1 .. 3)
    {
        foreach (x; 1 .. 3)
        {
            const offset =
                y * testWidth + x;

            assert(
                singleBand4x3[offset]
                == roiBand0_x1_y1_w2_h2[i]
            );

            ++i;
        }
    }

    assert(i == roiBand0_x1_y1_w2_h2.length);
}


} // version (unittest)
