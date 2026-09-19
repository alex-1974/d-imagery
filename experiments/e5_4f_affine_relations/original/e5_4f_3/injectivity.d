module injectivity;

import std.stdio :
    writeln;


@safe
pure
nothrow
@nogc
size_t signedMagnitude(
    ptrdiff_t value
)
{
    if (value >= 0)
        return cast(size_t) value;

    if (value == ptrdiff_t.min)
    {
        return
            cast(size_t) ptrdiff_t.max
            + 1;
    }

    return cast(size_t)(-value);
}


@safe
pure
nothrow
@nogc
size_t gcd(
    size_t a,
    size_t b
)
{
    while (b != 0)
    {
        const remainder =
            a % b;

        a = b;
        b = remainder;
    }

    return a;
}


/*
 * Exact injectivity criterion for the finite affine 2D mapping:
 *
 *     offset(x,y)
 *         = x * sampleStride
 *         + y * rowStride
 *
 * where:
 *
 *     0 <= x < width
 *     0 <= y < height
 *
 * Empty and single-sample regions are vacuously injective.
 */
@safe
pure
nothrow
@nogc
bool affine2DMappingIsInjective(
    size_t width,
    size_t height,
    ptrdiff_t rowStride,
    ptrdiff_t sampleStride
)
{
    if (
        width == 0
        || height == 0
    )
    {
        return true;
    }

    if (
        width == 1
        && height == 1
    )
    {
        return true;
    }


    const rowMagnitude =
        signedMagnitude(rowStride);

    const sampleMagnitude =
        signedMagnitude(sampleStride);


    /*
     * Every logical coordinate maps to the same physical sample.
     */
    if (
        rowMagnitude == 0
        && sampleMagnitude == 0
    )
    {
        return false;
    }


    const common =
        gcd(
            rowMagnitude,
            sampleMagnitude
        );

    assert(common != 0);


    /*
     * Integer solutions of:
     *
     *     dx * sampleStride
     *       + dy * rowStride
     *       = 0
     *
     * have the primitive absolute displacement:
     *
     *     |dx| = |rowStride| / gcd
     *     |dy| = |sampleStride| / gcd
     *
     * A collision exists exactly when that primitive displacement fits
     * inside both finite logical extents.
     */
    const collisionDx =
        rowMagnitude / common;

    const collisionDy =
        sampleMagnitude / common;


    const collisionExists =
           collisionDx <= width - 1
        && collisionDy <= height - 1;

    return !collisionExists;
}


/*
 * Brute-force reference used only by this research probe.
 */
@safe
pure
nothrow
@nogc
bool bruteForceInjective(
    size_t width,
    size_t height,
    ptrdiff_t rowStride,
    ptrdiff_t sampleStride
)
{
    foreach (y1; 0 .. height)
    {
        foreach (x1; 0 .. width)
        {
            const first =
                  cast(ptrdiff_t) x1 * sampleStride
                + cast(ptrdiff_t) y1 * rowStride;

            foreach (y2; 0 .. height)
            {
                foreach (x2; 0 .. width)
                {
                    if (
                        x1 == x2
                        && y1 == y2
                    )
                    {
                        continue;
                    }


                    const second =
                          cast(ptrdiff_t) x2 * sampleStride
                        + cast(ptrdiff_t) y2 * rowStride;

                    if (first == second)
                        return false;
                }
            }
        }
    }

    return true;
}


@safe
void main()
{
    size_t cases;


    /*
     * Exhaustive small-domain comparison.
     *
     * This covers:
     *
     * - empty dimensions;
     * - one-dimensional logical shapes;
     * - zero strides;
     * - positive strides;
     * - negative strides;
     * - mutually divisible strides;
     * - non-coprime strides;
     * - padded and overlapping rows.
     */
    foreach (width; 0 .. 7)
    {
        foreach (height; 0 .. 7)
        {
            foreach (
                rowStride;
                cast(ptrdiff_t) -12
                ..
                cast(ptrdiff_t) 13
            )
            {
                foreach (
                    sampleStride;
                    cast(ptrdiff_t) -12
                    ..
                    cast(ptrdiff_t) 13
                )
                {
                    const predicted =
                        affine2DMappingIsInjective(
                            width,
                            height,
                            rowStride,
                            sampleStride
                        );

                    const reference =
                        bruteForceInjective(
                            width,
                            height,
                            rowStride,
                            sampleStride
                        );

                    assert(
                        predicted
                        == reference
                    );

                    ++cases;
                }
            }
        }
    }


    /*
     * Important named cases.
     */

    assert(
        affine2DMappingIsInjective(
            4,
            3,
            4,
            1
        )
    );

    assert(
        affine2DMappingIsInjective(
            4,
            3,
            -4,
            1
        )
    );

    assert(
        !affine2DMappingIsInjective(
            4,
            3,
            0,
            1
        )
    );

    assert(
        !affine2DMappingIsInjective(
            4,
            3,
            4,
            0
        )
    );

    assert(
        !affine2DMappingIsInjective(
            3,
            2,
            2,
            1
        )
    );

    assert(
        !affine2DMappingIsInjective(
            4,
            3,
            6,
            4
        )
    );

    assert(
        affine2DMappingIsInjective(
            2,
            3,
            3,
            2
        )
    );


    writeln(
        "verifiedCases=",
        cases
    );

    writeln(
        "affine2D injectivity formula: PASS"
    );
}
