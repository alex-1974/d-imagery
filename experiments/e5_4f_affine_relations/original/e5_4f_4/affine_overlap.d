module affine_overlap;

import std.stdio :
    writeln;


struct Bezout
{
    long gcd;
    long x;
    long y;
}


@safe
pure
nothrow
@nogc
Bezout extendedGcd(
    long a,
    long b
)
{
    /*
     * Research probe domain is deliberately small.
     *
     * Production overflow handling is a later E5.4f gate.
     */
    long aa =
        a < 0 ? -a : a;

    long bb =
        b < 0 ? -b : b;

    long oldR = aa;
    long r = bb;

    long oldS = 1;
    long s = 0;

    long oldT = 0;
    long t = 1;


    while (r != 0)
    {
        const q =
            oldR / r;

        const nextR =
            oldR - q * r;

        oldR = r;
        r = nextR;


        const nextS =
            oldS - q * s;

        oldS = s;
        s = nextS;


        const nextT =
            oldT - q * t;

        oldT = t;
        t = nextT;
    }


    if (a < 0)
        oldS = -oldS;

    if (b < 0)
        oldT = -oldT;


    return Bezout(
        oldR,
        oldS,
        oldT
    );
}


@safe
pure
nothrow
@nogc
long floorDiv(
    long numerator,
    long denominator
)
{
    assert(denominator != 0);

    long quotient =
        numerator / denominator;

    const remainder =
        numerator % denominator;

    if (
        remainder != 0
        && (
            (remainder > 0)
            !=
            (denominator > 0)
        )
    )
    {
        --quotient;
    }

    return quotient;
}


@safe
pure
nothrow
@nogc
long ceilDiv(
    long numerator,
    long denominator
)
{
    assert(denominator != 0);

    long quotient =
        numerator / denominator;

    const remainder =
        numerator % denominator;

    if (
        remainder != 0
        && (
            (remainder > 0)
            ==
            (denominator > 0)
        )
    )
    {
        ++quotient;
    }

    return quotient;
}


/*
 * Restricts:
 *
 *     value = origin + step * k
 *
 * to:
 *
 *     lower <= value <= upper
 *
 * and returns the resulting inclusive integer k interval.
 */
@safe
pure
nothrow
@nogc
bool constrainParameter(
    long origin,
    long step,
    long lower,
    long upper,
    out long kMinimum,
    out long kMaximum
)
{
    if (step == 0)
    {
        if (
            origin < lower
            || origin > upper
        )
        {
            return false;
        }

        kMinimum =
            long.min;

        kMaximum =
            long.max;

        return true;
    }


    if (step > 0)
    {
        kMinimum =
            ceilDiv(
                lower - origin,
                step
            );

        kMaximum =
            floorDiv(
                upper - origin,
                step
            );
    }
    else
    {
        kMinimum =
            ceilDiv(
                upper - origin,
                step
            );

        kMaximum =
            floorDiv(
                lower - origin,
                step
            );
    }


    return kMinimum <= kMaximum;
}


/*
 * Exact bounded two-variable linear Diophantine feasibility:
 *
 *     a * i + b * j = value
 *
 * with:
 *
 *     0 <= i < firstCount
 *     0 <= j < secondCount
 */
@safe
pure
nothrow
@nogc
bool boundedLinearEquationHasSolution(
    long a,
    long b,
    long value,
    size_t firstCount,
    size_t secondCount
)
{
    if (
        firstCount == 0
        || secondCount == 0
    )
    {
        return false;
    }


    if (
        a == 0
        && b == 0
    )
    {
        return value == 0;
    }


    const bezout =
        extendedGcd(
            a,
            b
        );

    assert(bezout.gcd > 0);


    if (value % bezout.gcd != 0)
        return false;


    const scale =
        value / bezout.gcd;


    const firstOrigin =
        bezout.x * scale;

    const secondOrigin =
        bezout.y * scale;


    /*
     * General integer solution:
     *
     *     i = i0 + (b / gcd) * k
     *     j = j0 - (a / gcd) * k
     */
    const firstStep =
        b / bezout.gcd;

    const secondStep =
        -a / bezout.gcd;


    long firstKMinimum;
    long firstKMaximum;

    if (
        !constrainParameter(
            firstOrigin,
            firstStep,
            0,
            cast(long) firstCount - 1,
            firstKMinimum,
            firstKMaximum
        )
    )
    {
        return false;
    }


    long secondKMinimum;
    long secondKMaximum;

    if (
        !constrainParameter(
            secondOrigin,
            secondStep,
            0,
            cast(long) secondCount - 1,
            secondKMinimum,
            secondKMaximum
        )
    )
    {
        return false;
    }


    const combinedMinimum =
        firstKMinimum > secondKMinimum
        ? firstKMinimum
        : secondKMinimum;

    const combinedMaximum =
        firstKMaximum < secondKMaximum
        ? firstKMaximum
        : secondKMaximum;


    return combinedMinimum <= combinedMaximum;
}


/*
 * Exact overlap test for two finite one-dimensional strided sample lines.
 *
 * Source sample starts:
 *
 *     sourceBase + i * sourceStep
 *
 * Target sample starts:
 *
 *     targetBase + j * targetStep
 *
 * Each logical sample occupies a half-open byte interval.
 */
@safe
pure
nothrow
@nogc
bool lineSampleBytesOverlap(
    long sourceBase,
    long sourceStep,
    size_t sourceCount,
    size_t sourceSampleSize,
    long targetBase,
    long targetStep,
    size_t targetCount,
    size_t targetSampleSize
)
{
    if (
        sourceCount == 0
        || targetCount == 0
    )
    {
        return false;
    }


    /*
     * Two sample byte intervals overlap exactly when:
     *
     *     sourceStart - targetStart
     *
     * lies in:
     *
     *     [-(sourceSampleSize - 1),
     *        targetSampleSize - 1]
     */
    const minimumDifference =
        -cast(long)(
            sourceSampleSize - 1
        );

    const maximumDifference =
        cast(long)(
            targetSampleSize - 1
        );


    for (
        long difference = minimumDifference;
        difference <= maximumDifference;
        ++difference
    )
    {
        /*
         * sourceBase + i*sourceStep
         *   - (targetBase + j*targetStep)
         *     = difference
         *
         * therefore:
         *
         * sourceStep*i - targetStep*j
         *     = targetBase - sourceBase + difference
         */
        if (
            boundedLinearEquationHasSolution(
                sourceStep,
                -targetStep,
                targetBase
                    - sourceBase
                    + difference,
                sourceCount,
                targetCount
            )
        )
        {
            return true;
        }
    }


    return false;
}


/*
 * Exact relation for two equally shaped affine 2D raster views.
 *
 * Strides are expressed in logical elements, matching PlaneDescriptor.
 *
 * The view with width >= height is decomposed into rows.
 * Otherwise it is decomposed into columns.
 *
 * This gives:
 *
 *     min(width,height)
 *
 * one-dimensional lines per operand.
 */
@safe
pure
nothrow
@nogc
bool affine2DSampleBytesOverlap(
    size_t width,
    size_t height,

    long sourceBase,
    long sourceRowStrideElements,
    long sourceSampleStrideElements,
    size_t sourceSampleSize,

    long targetBase,
    long targetRowStrideElements,
    long targetSampleStrideElements,
    size_t targetSampleSize
)
{
    if (
        width == 0
        || height == 0
    )
    {
        return false;
    }


    const sourceRowStep =
        sourceRowStrideElements
        * cast(long) sourceSampleSize;

    const sourceSampleStep =
        sourceSampleStrideElements
        * cast(long) sourceSampleSize;

    const targetRowStep =
        targetRowStrideElements
        * cast(long) targetSampleSize;

    const targetSampleStep =
        targetSampleStrideElements
        * cast(long) targetSampleSize;


    if (height <= width)
    {
        /*
         * Row decomposition.
         */
        foreach (sourceY; 0 .. height)
        {
            const sourceLineBase =
                sourceBase
                + cast(long) sourceY
                    * sourceRowStep;

            foreach (targetY; 0 .. height)
            {
                const targetLineBase =
                    targetBase
                    + cast(long) targetY
                        * targetRowStep;

                if (
                    lineSampleBytesOverlap(
                        sourceLineBase,
                        sourceSampleStep,
                        width,
                        sourceSampleSize,

                        targetLineBase,
                        targetSampleStep,
                        width,
                        targetSampleSize
                    )
                )
                {
                    return true;
                }
            }
        }
    }
    else
    {
        /*
         * Column decomposition.
         */
        foreach (sourceX; 0 .. width)
        {
            const sourceLineBase =
                sourceBase
                + cast(long) sourceX
                    * sourceSampleStep;

            foreach (targetX; 0 .. width)
            {
                const targetLineBase =
                    targetBase
                    + cast(long) targetX
                        * targetSampleStep;

                if (
                    lineSampleBytesOverlap(
                        sourceLineBase,
                        sourceRowStep,
                        height,
                        sourceSampleSize,

                        targetLineBase,
                        targetRowStep,
                        height,
                        targetSampleSize
                    )
                )
                {
                    return true;
                }
            }
        }
    }


    return false;
}


@safe
pure
nothrow
@nogc
bool byteIntervalsOverlap(
    long firstStart,
    size_t firstSize,
    long secondStart,
    size_t secondSize
)
{
    return
           firstStart
            < secondStart
                + cast(long) secondSize
        && secondStart
            < firstStart
                + cast(long) firstSize;
}


/*
 * Slow reference implementation for the research domain.
 */
@safe
pure
nothrow
@nogc
bool bruteForceAffine2DSampleBytesOverlap(
    size_t width,
    size_t height,

    long sourceBase,
    long sourceRowStrideElements,
    long sourceSampleStrideElements,
    size_t sourceSampleSize,

    long targetBase,
    long targetRowStrideElements,
    long targetSampleStrideElements,
    size_t targetSampleSize
)
{
    const sourceRowStep =
        sourceRowStrideElements
        * cast(long) sourceSampleSize;

    const sourceSampleStep =
        sourceSampleStrideElements
        * cast(long) sourceSampleSize;

    const targetRowStep =
        targetRowStrideElements
        * cast(long) targetSampleSize;

    const targetSampleStep =
        targetSampleStrideElements
        * cast(long) targetSampleSize;


    foreach (sourceY; 0 .. height)
    {
        foreach (sourceX; 0 .. width)
        {
            const sourceStart =
                  sourceBase
                + cast(long) sourceY
                    * sourceRowStep
                + cast(long) sourceX
                    * sourceSampleStep;


            foreach (targetY; 0 .. height)
            {
                foreach (targetX; 0 .. width)
                {
                    const targetStart =
                          targetBase
                        + cast(long) targetY
                            * targetRowStep
                        + cast(long) targetX
                            * targetSampleStep;


                    if (
                        byteIntervalsOverlap(
                            sourceStart,
                            sourceSampleSize,
                            targetStart,
                            targetSampleSize
                        )
                    )
                    {
                        return true;
                    }
                }
            }
        }
    }


    return false;
}


struct SampleSizePair
{
    size_t source;
    size_t target;
}


@safe
void main()
{
    immutable long[5] strides =
        [-2, -1, 0, 1, 2];

    immutable long[9] targetBaseDeltas =
        [-4, -3, -2, -1, 0, 1, 2, 3, 4];

    immutable SampleSizePair[4] sampleSizes =
    [
        SampleSizePair(1, 1),
        SampleSizePair(2, 2),
        SampleSizePair(3, 3),
        SampleSizePair(1, 4)
    ];


    size_t verifiedCases;


    /*
     * Exhaustive small-domain comparison of the exact arithmetic method with
     * explicit sample-pair enumeration.
     *
     * Includes:
     *
     * - empty regions;
     * - row and column decomposition;
     * - positive, negative and zero strides;
     * - self-aliasing sources and targets;
     * - same-size copy samples;
     * - 3-byte POD-like samples;
     * - ubyte -> float sized samples;
     * - offset bases;
     * - partial byte overlap.
     */
    foreach (size_t width; 0 .. 4)
    {
        foreach (size_t height; 0 .. 4)
        {
            foreach (
                sourceRowStride;
                strides
            )
            {
                foreach (
                    sourceSampleStride;
                    strides
                )
                {
                    foreach (
                        targetRowStride;
                        strides
                    )
                    {
                        foreach (
                            targetSampleStride;
                            strides
                        )
                        {
                            foreach (
                                targetBaseDelta;
                                targetBaseDeltas
                            )
                            {
                                foreach (
                                    sampleSize;
                                    sampleSizes
                                )
                                {
                                    const exact =
                                        affine2DSampleBytesOverlap(
                                            width,
                                            height,

                                            0,
                                            sourceRowStride,
                                            sourceSampleStride,
                                            sampleSize.source,

                                            targetBaseDelta,
                                            targetRowStride,
                                            targetSampleStride,
                                            sampleSize.target
                                        );


                                    const reference =
                                        bruteForceAffine2DSampleBytesOverlap(
                                            width,
                                            height,

                                            0,
                                            sourceRowStride,
                                            sourceSampleStride,
                                            sampleSize.source,

                                            targetBaseDelta,
                                            targetRowStride,
                                            targetSampleStride,
                                            sampleSize.target
                                        );


                                    assert(
                                        exact
                                        == reference
                                    );


                                    ++verifiedCases;
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    /*
     * Bounding envelopes overlap, but actual samples are disjoint:
     *
     * source: 0,2,4,6
     * target: 1,3,5,7
     */
    assert(
        !affine2DSampleBytesOverlap(
            4,
            1,

            0,
            0,
            2,
            1,

            1,
            0,
            2,
            1
        )
    );


    /*
     * Actual interleaved sample overlap.
     */
    assert(
        affine2DSampleBytesOverlap(
            4,
            1,

            0,
            0,
            2,
            1,

            2,
            0,
            2,
            1
        )
    );


    /*
     * Same physical sample order, opposite logical traversal.
     */
    assert(
        affine2DSampleBytesOverlap(
            4,
            1,

            6,
            0,
            -2,
            1,

            0,
            0,
            2,
            1
        )
    );


    /*
     * ubyte source samples exactly intersect float destination samples.
     */
    assert(
        affine2DSampleBytesOverlap(
            4,
            1,

            0,
            0,
            4,
            1,

            0,
            0,
            1,
            4
        )
    );


    writeln(
        "verifiedCases=",
        verifiedCases
    );

    writeln(
        "exact affine 2D byte-overlap relation: PASS"
    );
}
