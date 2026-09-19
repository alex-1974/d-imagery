module wide_signed;

import core.int128 :
    Cent,
    Zero,
    add,
    mul,
    sub,
    tst,
    udivmod,
    uge,
    ugt,
    ult;

import std.stdio :
    writeln;


/*
 * Research-only signed wide integer:
 *
 *     sign + unsigned 128-bit magnitude
 *
 * Zero is always normalized to non-negative.
 *
 * This is deliberately not a production type.
 */
struct SignedWide
{
    bool negative;
    Cent magnitude;
}


@safe
pure
nothrow
@nogc
Cent u128(
    ulong value
)
{
    return Cent(
        lo: value,
        hi: 0
    );
}


@safe
pure
nothrow
@nogc
SignedWide makeSignedWide(
    bool negative,
    Cent magnitude
)
{
    if (!tst(magnitude))
        negative = false;

    return SignedWide(
        negative,
        magnitude
    );
}


@safe
pure
nothrow
@nogc
SignedWide zeroWide()
{
    return SignedWide(
        false,
        Zero
    );
}


@safe
pure
nothrow
@nogc
int compareMagnitude(
    Cent left,
    Cent right
)
{
    if (ult(left, right))
        return -1;

    if (ugt(left, right))
        return 1;

    return 0;
}


@safe
pure
nothrow
@nogc
int compareSigned(
    SignedWide left,
    SignedWide right
)
{
    if (
        !tst(left.magnitude)
        && !tst(right.magnitude)
    )
    {
        return 0;
    }

    if (left.negative != right.negative)
        return left.negative ? -1 : 1;

    const magnitudeComparison =
        compareMagnitude(
            left.magnitude,
            right.magnitude
        );

    return left.negative
        ? -magnitudeComparison
        : magnitudeComparison;
}


/*
 * Checked unsigned-128 addition.
 *
 * core.int128.add itself is modulo 2^128, so unsigned wrap is detected by
 * comparing the result with either operand.
 */
@safe
pure
nothrow
@nogc
bool tryAddMagnitude(
    Cent left,
    Cent right,
    out Cent result
)
{
    result =
        add(
            left,
            right
        );

    if (
        ult(result, left)
        || ult(result, right)
    )
    {
        result = Zero;
        return false;
    }

    return true;
}


/*
 * Exact magnitude subtraction.
 */
@safe
pure
nothrow
@nogc
Cent subtractMagnitude(
    Cent left,
    Cent right
)
{
    assert(uge(left, right));

    return sub(
        left,
        right
    );
}


@safe
pure
nothrow
@nogc
SignedWide negateWide(
    SignedWide value
)
{
    if (!tst(value.magnitude))
        return value;

    value.negative =
        !value.negative;

    return value;
}


/*
 * Checked sign+magnitude addition.
 *
 * Failure means the mathematical magnitude exceeds the unsigned 128-bit
 * carrier.
 */
@safe
pure
nothrow
@nogc
bool tryAddSigned(
    SignedWide left,
    SignedWide right,
    out SignedWide result
)
{
    result =
        zeroWide();

    if (left.negative == right.negative)
    {
        Cent magnitude;

        if (
            !tryAddMagnitude(
                left.magnitude,
                right.magnitude,
                magnitude
            )
        )
        {
            return false;
        }

        result =
            makeSignedWide(
                left.negative,
                magnitude
            );

        return true;
    }


    const relation =
        compareMagnitude(
            left.magnitude,
            right.magnitude
        );

    if (relation == 0)
    {
        result =
            zeroWide();

        return true;
    }


    if (relation > 0)
    {
        result =
            makeSignedWide(
                left.negative,
                subtractMagnitude(
                    left.magnitude,
                    right.magnitude
                )
            );
    }
    else
    {
        result =
            makeSignedWide(
                right.negative,
                subtractMagnitude(
                    right.magnitude,
                    left.magnitude
                )
            );
    }

    return true;
}


@safe
pure
nothrow
@nogc
bool trySubtractSigned(
    SignedWide left,
    SignedWide right,
    out SignedWide result
)
{
    return tryAddSigned(
        left,
        negateWide(right),
        result
    );
}


@safe
pure
nothrow
@nogc
ulong signedMachineMagnitude(
    long value
)
{
    if (value >= 0)
        return cast(ulong) value;

    if (value == long.min)
    {
        return
            cast(ulong) long.max
            + 1;
    }

    return cast(ulong)(-value);
}


@safe
pure
nothrow
@nogc
SignedWide fromLong(
    long value
)
{
    return makeSignedWide(
        value < 0,
        u128(
            signedMachineMagnitude(value)
        )
    );
}


@safe
pure
nothrow
@nogc
size_t ptrdiffMagnitude(
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
SignedWide fromPtrdiff(
    ptrdiff_t value
)
{
    return makeSignedWide(
        value < 0,
        u128(
            cast(ulong)
                ptrdiffMagnitude(value)
        )
    );
}


/*
 * Exact difference of two machine-word addresses without first narrowing the
 * difference into ptrdiff_t.
 */
@safe
pure
nothrow
@nogc
SignedWide addressDifference(
    size_t left,
    size_t right
)
{
    if (left >= right)
    {
        return makeSignedWide(
            false,
            u128(
                cast(ulong)(
                    left - right
                )
            )
        );
    }

    return makeSignedWide(
        true,
        u128(
            cast(ulong)(
                right - left
            )
        )
    );
}


/*
 * Exact:
 *
 *     signed ptrdiff stride * unsigned machine-word factor
 *
 * The 64-bit-host maximum is:
 *
 *     2^63 * (2^64 - 1) < 2^127
 *
 * and therefore fits the unsigned 128-bit magnitude carrier.
 */
@safe
pure
nothrow
@nogc
SignedWide multiplyPtrdiffBySize(
    ptrdiff_t value,
    size_t factor
)
{
    const magnitude =
        mul(
            u128(
                cast(ulong)
                    ptrdiffMagnitude(value)
            ),
            u128(
                cast(ulong) factor
            )
        );

    return makeSignedWide(
        value < 0,
        magnitude
    );
}


@safe
pure
nothrow
@nogc
bool tryIncrementMagnitude(
    Cent value,
    out Cent result
)
{
    return tryAddMagnitude(
        value,
        u128(1),
        result
    );
}


/*
 * Mathematical floor division.
 *
 * Denominator may be positive or negative but must not be zero.
 */
@safe
pure
nothrow
@nogc
bool tryFloorDivide(
    SignedWide numerator,
    SignedWide denominator,
    out SignedWide result
)
{
    result =
        zeroWide();

    if (!tst(denominator.magnitude))
        return false;

    Cent remainder;

    const quotientMagnitude =
        udivmod(
            numerator.magnitude,
            denominator.magnitude,
            remainder
        );

    const negative =
        numerator.negative
        != denominator.negative;


    if (
        negative
        && tst(remainder)
    )
    {
        Cent adjusted;

        if (
            !tryIncrementMagnitude(
                quotientMagnitude,
                adjusted
            )
        )
        {
            return false;
        }

        result =
            makeSignedWide(
                true,
                adjusted
            );

        return true;
    }


    result =
        makeSignedWide(
            negative,
            quotientMagnitude
        );

    return true;
}


/*
 * Mathematical ceil division.
 */
@safe
pure
nothrow
@nogc
bool tryCeilDivide(
    SignedWide numerator,
    SignedWide denominator,
    out SignedWide result
)
{
    result =
        zeroWide();

    if (!tst(denominator.magnitude))
        return false;

    Cent remainder;

    const quotientMagnitude =
        udivmod(
            numerator.magnitude,
            denominator.magnitude,
            remainder
        );

    const negative =
        numerator.negative
        != denominator.negative;


    if (
        !negative
        && tst(remainder)
    )
    {
        Cent adjusted;

        if (
            !tryIncrementMagnitude(
                quotientMagnitude,
                adjusted
            )
        )
        {
            return false;
        }

        result =
            makeSignedWide(
                false,
                adjusted
            );

        return true;
    }


    result =
        makeSignedWide(
            negative,
            quotientMagnitude
        );

    return true;
}


/*
 * Small-domain conversion used only by the independent reference comparison.
 */
@safe
pure
nothrow
@nogc
bool tryToLong(
    SignedWide value,
    out long result
)
{
    result = 0;

    if (value.magnitude.hi != 0)
        return false;

    const magnitude =
        value.magnitude.lo;


    if (!value.negative)
    {
        if (
            magnitude
            > cast(ulong) long.max
        )
        {
            return false;
        }

        result =
            cast(long) magnitude;

        return true;
    }


    const minimumMagnitude =
        cast(ulong) long.max
        + 1;


    if (magnitude > minimumMagnitude)
        return false;

    if (magnitude == minimumMagnitude)
    {
        result =
            long.min;

        return true;
    }


    result =
        -cast(long) magnitude;

    return true;
}


/*
 * Independent narrow-domain reference.
 */
@safe
pure
nothrow
@nogc
long referenceFloorDivide(
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
long referenceCeilDivide(
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


@safe
void main()
{
    static assert(
        size_t.sizeof
        <= ulong.sizeof
    );

    static assert(
        ptrdiff_t.sizeof
        <= long.sizeof
    );


    size_t arithmeticCases;
    size_t divisionCases;


    /*
     * Exhaustive small-domain signed add/subtract equivalence.
     */
    foreach (
        long left;
        -100
        ..
        101
    )
    {
        foreach (
            long right;
            -100
            ..
            101
        )
        {
            SignedWide wideResult;
            long narrowResult;


            assert(
                tryAddSigned(
                    fromLong(left),
                    fromLong(right),
                    wideResult
                )
            );

            assert(
                tryToLong(
                    wideResult,
                    narrowResult
                )
            );

            assert(
                narrowResult
                == left + right
            );


            assert(
                trySubtractSigned(
                    fromLong(left),
                    fromLong(right),
                    wideResult
                )
            );

            assert(
                tryToLong(
                    wideResult,
                    narrowResult
                )
            );

            assert(
                narrowResult
                == left - right
            );


            ++arithmeticCases;
        }
    }


    /*
     * Exhaustive small-domain floor/ceil equivalence.
     */
    foreach (
        long numerator;
        -100
        ..
        101
    )
    {
        foreach (
            long denominator;
            -20
            ..
        21
        )
        {
            if (denominator == 0)
                continue;


            SignedWide wideFloor;
            SignedWide wideCeil;

            assert(
                tryFloorDivide(
                    fromLong(numerator),
                    fromLong(denominator),
                    wideFloor
                )
            );

            assert(
                tryCeilDivide(
                    fromLong(numerator),
                    fromLong(denominator),
                    wideCeil
                )
            );


            long floorValue;
            long ceilValue;

            assert(
                tryToLong(
                    wideFloor,
                    floorValue
                )
            );

            assert(
                tryToLong(
                    wideCeil,
                    ceilValue
                )
            );


            assert(
                floorValue
                == referenceFloorDivide(
                    numerator,
                    denominator
                )
            );

            assert(
                ceilValue
                == referenceCeilDivide(
                    numerator,
                    denominator
                )
            );


            ++divisionCases;
        }
    }


    /*
     * Full machine-address difference:
     *
     * no ptrdiff_t narrowing occurs.
     */
    const maximumAddressDifference =
        addressDifference(
            size_t.max,
            0
        );

    assert(
        !maximumAddressDifference.negative
    );

    assert(
        maximumAddressDifference.magnitude.hi
        == 0
    );

    assert(
        maximumAddressDifference.magnitude.lo
        == cast(ulong) size_t.max
    );


    const minimumAddressDifference =
        addressDifference(
            0,
            size_t.max
        );

    assert(
        minimumAddressDifference.negative
    );

    assert(
        minimumAddressDifference.magnitude.hi
        == 0
    );

    assert(
        minimumAddressDifference.magnitude.lo
        == cast(ulong) size_t.max
    );


    /*
     * ptrdiff_t.min is handled without evaluating -ptrdiff_t.min.
     */
    const minimumPtrdiff =
        fromPtrdiff(
            ptrdiff_t.min
        );

    assert(minimumPtrdiff.negative);

    assert(
        minimumPtrdiff.magnitude.hi
        == 0
    );

    assert(
        minimumPtrdiff.magnitude.lo
        ==
            cast(ulong) ptrdiff_t.max
            + 1
    );


    /*
     * Maximum relevant raw signed-stride x unsigned-size product.
     */
    const wideProduct =
        multiplyPtrdiffBySize(
            ptrdiff_t.min,
            size_t.max
        );

    assert(wideProduct.negative);

    static if (
        ptrdiff_t.sizeof == 8
        && size_t.sizeof == 8
    )
    {
        /*
         * 2^63 * (2^64 - 1)
         *
         * = high 64 bits 0x7fff_ffff_ffff_ffff
         *   low  64 bits 0x8000_0000_0000_0000
         */
        assert(
            wideProduct.magnitude.hi
            == 0x7fff_ffff_ffff_ffffUL
        );

        assert(
            wideProduct.magnitude.lo
            == 0x8000_0000_0000_0000UL
        );
    }


    /*
     * Mixed-sign cancellation across full machine-address magnitudes.
     */
    SignedWide cancellation;

    assert(
        tryAddSigned(
            maximumAddressDifference,
            minimumAddressDifference,
            cancellation
        )
    );

    assert(
        !cancellation.negative
    );

    assert(
        !tst(cancellation.magnitude)
    );


    /*
     * Detect unsigned-128 overflow instead of silently wrapping.
     */
    const maximumMagnitude =
        Cent(
            lo: ulong.max,
            hi: ulong.max
        );

    SignedWide overflowResult;

    assert(
        !tryAddSigned(
            makeSignedWide(
                false,
                maximumMagnitude
            ),
            fromLong(1),
            overflowResult
        )
    );


    /*
     * Wide floor/ceil beyond signed machine range.
     */
    const largePositive =
        makeSignedWide(
            false,
            Cent(
                lo: 0,
                hi: 1
            )
        );

    const largeNegative =
        negateWide(
            largePositive
        );


    SignedWide floorResult;
    SignedWide ceilResult;

    assert(
        tryFloorDivide(
            largeNegative,
            fromLong(3),
            floorResult
        )
    );

    assert(
        tryCeilDivide(
            largeNegative,
            fromLong(3),
            ceilResult
        )
    );

    assert(
        compareSigned(
            floorResult,
            ceilResult
        )
        < 0
    );


    writeln(
        "arithmeticCases=",
        arithmeticCases
    );

    writeln(
        "divisionCases=",
        divisionCases
    );

    writeln(
        "sign+magnitude Cent arithmetic: PASS"
    );

    writeln(
        "address difference without signed narrowing: PASS"
    );

    writeln(
        "ptrdiff.min magnitude handling: PASS"
    );

    writeln(
        "wide floor/ceil division: PASS"
    );
}
