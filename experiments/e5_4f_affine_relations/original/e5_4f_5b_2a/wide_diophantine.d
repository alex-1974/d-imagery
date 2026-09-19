module wide_diophantine;

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



struct SignedWord
{
    bool negative;
    ulong magnitude;
}


@safe
pure
nothrow
@nogc
SignedWord makeSignedWord(
    bool negative,
    ulong magnitude
)
{
    if (magnitude == 0)
        negative = false;

    return SignedWord(
        negative,
        magnitude
    );
}


@safe
pure
nothrow
@nogc
SignedWord wordFromLong(
    long value
)
{
    return makeSignedWord(
        value < 0,
        signedMachineMagnitude(value)
    );
}


@safe
pure
nothrow
@nogc
SignedWide fromUnsignedWord(
    ulong value
)
{
    return makeSignedWide(
        false,
        u128(value)
    );
}


@safe
pure
nothrow
@nogc
SignedWide fromSize(
    size_t value
)
{
    return fromUnsignedWord(
        cast(ulong) value
    );
}


@safe
pure
nothrow
@nogc
SignedWide fromSignedWord(
    SignedWord value
)
{
    return makeSignedWide(
        value.negative,
        u128(value.magnitude)
    );
}


@safe
pure
nothrow
@nogc
ulong gcdWord(
    ulong left,
    ulong right
)
{
    while (right != 0)
    {
        const remainder =
            left % right;

        left = right;
        right = remainder;
    }

    return left;
}


@safe
pure
nothrow
@nogc
Cent divideMagnitudeByWord(
    Cent numerator,
    ulong denominator,
    out ulong remainder
)
{
    assert(denominator != 0);

    Cent wideRemainder;

    const quotient =
        udivmod(
            numerator,
            u128(denominator),
            wideRemainder
        );

    assert(wideRemainder.hi == 0);

    remainder =
        wideRemainder.lo;

    return quotient;
}


@safe
pure
nothrow
@nogc
ulong remainderMagnitudeByWord(
    Cent numerator,
    ulong denominator
)
{
    ulong remainder;

    cast(void)
        divideMagnitudeByWord(
            numerator,
            denominator,
            remainder
        );

    return remainder;
}


/*
 * Checked:
 *
 *     unsigned-128 magnitude * unsigned machine word
 */
@safe
pure
nothrow
@nogc
bool tryMultiplyMagnitudeByWord(
    Cent value,
    ulong factor,
    out Cent result
)
{
    result = Zero;

    if (
        factor == 0
        || !tst(value)
    )
    {
        return true;
    }


    result =
        mul(
            value,
            u128(factor)
        );


    Cent remainder;

    const recovered =
        udivmod(
            result,
            u128(factor),
            remainder
        );


    if (
        tst(remainder)
        || compareMagnitude(
            recovered,
            value
        ) != 0
    )
    {
        result = Zero;
        return false;
    }


    return true;
}


@safe
pure
nothrow
@nogc
bool tryMultiplySignedByWord(
    SignedWide value,
    ulong factor,
    out SignedWide result
)
{
    result =
        zeroWide();

    Cent magnitude;

    if (
        !tryMultiplyMagnitudeByWord(
            value.magnitude,
            factor,
            magnitude
        )
    )
    {
        return false;
    }


    result =
        makeSignedWide(
            value.negative,
            magnitude
        );

    return true;
}


@safe
pure
nothrow
@nogc
ulong moduloSignedWide(
    SignedWide value,
    ulong modulus
)
{
    assert(modulus != 0);

    if (modulus == 1)
        return 0;


    const remainder =
        remainderMagnitudeByWord(
            value.magnitude,
            modulus
        );


    if (
        !value.negative
        || remainder == 0
    )
    {
        return remainder;
    }


    return modulus - remainder;
}


@safe
pure
nothrow
@nogc
ulong moduloSignedWord(
    SignedWord value,
    ulong modulus
)
{
    assert(modulus != 0);

    if (modulus == 1)
        return 0;


    const remainder =
        value.magnitude % modulus;


    if (
        !value.negative
        || remainder == 0
    )
    {
        return remainder;
    }


    return modulus - remainder;
}


/*
 * Multiplication modulo one machine-word modulus.
 *
 * Both operands are machine words, therefore the complete product fits the
 * unsigned 128-bit carrier before reduction.
 */
@safe
pure
nothrow
@nogc
ulong multiplyWordsModulo(
    ulong left,
    ulong right,
    ulong modulus
)
{
    assert(modulus != 0);

    if (modulus == 1)
        return 0;


    const product =
        mul(
            u128(left),
            u128(right)
        );


    return remainderMagnitudeByWord(
        product,
        modulus
    );
}


/*
 * Modular inverse using Euclid while coefficients remain sign+magnitude
 * wide values.
 *
 * This function is called only for values known to be coprime to modulus.
 * Returning false therefore means an arithmetic-carrier failure, not an
 * ordinary "no inverse" result.
 */
@safe
pure
nothrow
@nogc
bool tryModularInverseWord(
    ulong value,
    ulong modulus,
    out ulong inverse
)
{
    inverse = 0;

    assert(modulus != 0);

    if (modulus == 1)
        return true;


    value %=
        modulus;

    if (value == 0)
        return false;


    SignedWide t =
        zeroWide();

    SignedWide newT =
        fromLong(1);

    ulong r =
        modulus;

    ulong newR =
        value;


    while (newR != 0)
    {
        const quotient =
            r / newR;


        SignedWide scaledNewT;

        if (
            !tryMultiplySignedByWord(
                newT,
                quotient,
                scaledNewT
            )
        )
        {
            return false;
        }


        SignedWide nextT;

        if (
            !trySubtractSigned(
                t,
                scaledNewT,
                nextT
            )
        )
        {
            return false;
        }


        const nextR =
            r
            - quotient * newR;


        t = newT;
        newT = nextT;

        r = newR;
        newR = nextR;
    }


    if (r != 1)
        return false;


    inverse =
        moduloSignedWide(
            t,
            modulus
        );

    return true;
}


@safe
pure
nothrow
@nogc
bool tryDivideExactBySignedWord(
    SignedWide numerator,
    SignedWord denominator,
    out SignedWide quotient
)
{
    quotient =
        zeroWide();

    if (denominator.magnitude == 0)
        return false;


    ulong remainder;

    const magnitude =
        divideMagnitudeByWord(
            numerator.magnitude,
            denominator.magnitude,
            remainder
        );


    if (remainder != 0)
        return false;


    quotient =
        makeSignedWide(
            numerator.negative
                != denominator.negative,
            magnitude
        );

    return true;
}


@safe
pure
nothrow
@nogc
bool coordinateWithinCount(
    SignedWide coordinate,
    size_t count
)
{
    if (count == 0)
        return false;

    if (coordinate.negative)
        return false;


    const maximum =
        fromSize(
            count - 1
        );


    return compareSigned(
        coordinate,
        maximum
    ) <= 0;
}


enum ParameterIntervalStatus : ubyte
{
    empty,

    nonEmpty,

    arithmeticFailure
}


/*
 * Finds all integer k for which:
 *
 *     0 <= origin + step*k < count
 *
 * Step must be non-zero.
 */
@safe
pure
nothrow
@nogc
ParameterIntervalStatus parameterInterval(
    SignedWide origin,
    SignedWide step,
    size_t count,
    out SignedWide minimum,
    out SignedWide maximum
)
{
    minimum =
        zeroWide();

    maximum =
        zeroWide();


    if (count == 0)
        return ParameterIntervalStatus.empty;


    assert(tst(step.magnitude));


    const lower =
        zeroWide();

    const upper =
        fromSize(
            count - 1
        );


    SignedWide lowerMinusOrigin;
    SignedWide upperMinusOrigin;


    if (
        !trySubtractSigned(
            lower,
            origin,
            lowerMinusOrigin
        )
        || !trySubtractSigned(
            upper,
            origin,
            upperMinusOrigin
        )
    )
    {
        return ParameterIntervalStatus.arithmeticFailure;
    }


    bool divisionOk;


    if (!step.negative)
    {
        divisionOk =
            tryCeilDivide(
                lowerMinusOrigin,
                step,
                minimum
            )
            &&
            tryFloorDivide(
                upperMinusOrigin,
                step,
                maximum
            );
    }
    else
    {
        divisionOk =
            tryCeilDivide(
                upperMinusOrigin,
                step,
                minimum
            )
            &&
            tryFloorDivide(
                lowerMinusOrigin,
                step,
                maximum
            );
    }


    if (!divisionOk)
        return ParameterIntervalStatus.arithmeticFailure;


    return compareSigned(
        minimum,
        maximum
    ) <= 0
        ? ParameterIntervalStatus.nonEmpty
        : ParameterIntervalStatus.empty;
}


enum DiophantineStatus : ubyte
{
    noSolution,

    hasSolution,

    arithmeticFailure
}


/*
 * Exact bounded feasibility for:
 *
 *     a*i + b*j = c
 *
 *     0 <= i < firstCount
 *     0 <= j < secondCount
 *
 * Coefficients are signed machine-word magnitudes.
 * c may use the full signed 128-bit sign+magnitude carrier.
 */
@safe
pure
nothrow
@nogc
DiophantineStatus boundedLinearEquation(
    SignedWord a,
    SignedWord b,
    SignedWide c,
    size_t firstCount,
    size_t secondCount
)
{
    if (
        firstCount == 0
        || secondCount == 0
    )
    {
        return DiophantineStatus.noSolution;
    }


    /*
     * Constant equation.
     */
    if (
        a.magnitude == 0
        && b.magnitude == 0
    )
    {
        return tst(c.magnitude)
            ? DiophantineStatus.noSolution
            : DiophantineStatus.hasSolution;
    }


    /*
     * One-variable special cases avoid artificial modular machinery.
     */
    if (b.magnitude == 0)
    {
        SignedWide coordinate;

        if (
            !tryDivideExactBySignedWord(
                c,
                a,
                coordinate
            )
        )
        {
            return DiophantineStatus.noSolution;
        }


        return coordinateWithinCount(
            coordinate,
            firstCount
        )
            ? DiophantineStatus.hasSolution
            : DiophantineStatus.noSolution;
    }


    if (a.magnitude == 0)
    {
        SignedWide coordinate;

        if (
            !tryDivideExactBySignedWord(
                c,
                b,
                coordinate
            )
        )
        {
            return DiophantineStatus.noSolution;
        }


        return coordinateWithinCount(
            coordinate,
            secondCount
        )
            ? DiophantineStatus.hasSolution
            : DiophantineStatus.noSolution;
    }


    const common =
        gcdWord(
            a.magnitude,
            b.magnitude
        );

    assert(common != 0);


    if (
        remainderMagnitudeByWord(
            c.magnitude,
            common
        ) != 0
    )
    {
        return DiophantineStatus.noSolution;
    }


    const reducedA =
        makeSignedWord(
            a.negative,
            a.magnitude / common
        );

    const reducedB =
        makeSignedWord(
            b.negative,
            b.magnitude / common
        );


    ulong reducedCRemainder;

    const reducedCMagnitude =
        divideMagnitudeByWord(
            c.magnitude,
            common,
            reducedCRemainder
        );

    assert(reducedCRemainder == 0);


    const reducedC =
        makeSignedWide(
            c.negative,
            reducedCMagnitude
        );


    /*
     * Solve:
     *
     *     reducedA * i = reducedC  (mod |reducedB|)
     *
     * and choose the canonical:
     *
     *     0 <= i0 < |reducedB|
     *
     * This avoids scaling arbitrary Bézout coefficients by c.
     */
    const periodI =
        reducedB.magnitude;

    assert(periodI != 0);


    ulong i0;


    if (periodI == 1)
    {
        i0 = 0;
    }
    else
    {
        const aResidue =
            moduloSignedWord(
                reducedA,
                periodI
            );

        const cResidue =
            moduloSignedWide(
                reducedC,
                periodI
            );


        ulong inverse;

        if (
            !tryModularInverseWord(
                aResidue,
                periodI,
                inverse
            )
        )
        {
            /*
             * gcd(reducedA, reducedB) == 1, so absence of an inverse would
             * indicate arithmetic failure.
             */
            return DiophantineStatus.arithmeticFailure;
        }


        i0 =
            multiplyWordsModulo(
                cResidue,
                inverse,
                periodI
            );
    }


    /*
     * Derive j0 from the exact reduced equation.
     */
    const aTimesI0 =
        makeSignedWide(
            reducedA.negative,
            mul(
                u128(reducedA.magnitude),
                u128(i0)
            )
        );


    SignedWide jNumerator;

    if (
        !trySubtractSigned(
            reducedC,
            aTimesI0,
            jNumerator
        )
    )
    {
        return DiophantineStatus.arithmeticFailure;
    }


    SignedWide j0;

    if (
        !tryDivideExactBySignedWord(
            jNumerator,
            reducedB,
            j0
        )
    )
    {
        /*
         * Congruence construction guarantees exact divisibility.
         */
        return DiophantineStatus.arithmeticFailure;
    }


    /*
     * Since i uses a positive period:
     *
     *     i = i0 + |reducedB| * k
     *
     * the corresponding j step is:
     *
     *     -reducedA * sign(reducedB)
     */
    const stepI =
        fromUnsignedWord(
            periodI
        );


    const stepJ =
        makeSignedWide(
            reducedA.negative
                == reducedB.negative,
            u128(
                reducedA.magnitude
            )
        );


    SignedWide firstMinimum;
    SignedWide firstMaximum;

    const firstInterval =
        parameterInterval(
            fromUnsignedWord(i0),
            stepI,
            firstCount,
            firstMinimum,
            firstMaximum
        );


    if (
        firstInterval
        == ParameterIntervalStatus.arithmeticFailure
    )
    {
        return DiophantineStatus.arithmeticFailure;
    }


    if (
        firstInterval
        == ParameterIntervalStatus.empty
    )
    {
        return DiophantineStatus.noSolution;
    }


    SignedWide secondMinimum;
    SignedWide secondMaximum;

    const secondInterval =
        parameterInterval(
            j0,
            stepJ,
            secondCount,
            secondMinimum,
            secondMaximum
        );


    if (
        secondInterval
        == ParameterIntervalStatus.arithmeticFailure
    )
    {
        return DiophantineStatus.arithmeticFailure;
    }


    if (
        secondInterval
        == ParameterIntervalStatus.empty
    )
    {
        return DiophantineStatus.noSolution;
    }


    /*
     * The two k intervals must intersect.
     */
    if (
        compareSigned(
            firstMinimum,
            secondMaximum
        ) > 0
        ||
        compareSigned(
            secondMinimum,
            firstMaximum
        ) > 0
    )
    {
        return DiophantineStatus.noSolution;
    }


    return DiophantineStatus.hasSolution;
}


/*
 * Independent narrow-domain oracle.
 */
@safe
pure
nothrow
@nogc
bool bruteForceBoundedLinearEquation(
    long a,
    long b,
    long c,
    size_t firstCount,
    size_t secondCount
)
{
    foreach (i; 0 .. firstCount)
    {
        foreach (j; 0 .. secondCount)
        {
            const value =
                  a * cast(long) i
                + b * cast(long) j;

            if (value == c)
                return true;
        }
    }

    return false;
}


@safe
void main()
{
    static assert(
        size_t.sizeof
        <= ulong.sizeof
    );


    size_t verifiedCases;


    /*
     * Exhaustive small-domain equivalence against an independent enumerating
     * oracle.
     *
     * Includes:
     *
     * - zero coefficients;
     * - positive/negative coefficients;
     * - positive/negative c;
     * - empty variable domains;
     * - gcd divisibility failures;
     * - solutions requiring non-zero parameter k.
     */
    foreach (
        long a;
        -9
        ..
        10
    )
    {
        foreach (
            long b;
            -9
            ..
            10
        )
        {
            foreach (
                long c;
                -30
                ..
                31
            )
            {
                foreach (
                    size_t firstCount;
                    0
                    ..
                    6
                )
                {
                    foreach (
                        size_t secondCount;
                        0
                        ..
                        6
                    )
                    {
                        const status =
                            boundedLinearEquation(
                                wordFromLong(a),
                                wordFromLong(b),
                                fromLong(c),
                                firstCount,
                                secondCount
                            );


                        assert(
                            status
                            != DiophantineStatus.arithmeticFailure
                        );


                        const expected =
                            bruteForceBoundedLinearEquation(
                                a,
                                b,
                                c,
                                firstCount,
                                secondCount
                            );


                        assert(
                            (
                                status
                                == DiophantineStatus.hasSolution
                            )
                            == expected
                        );


                        ++verifiedCases;
                    }
                }
            }
        }
    }


    /*
     * Full-width right-hand side:
     *
     *     U*i + j = 2^64
     *
     * solution:
     *
     *     i=1, j=1
     */
    static if (size_t.sizeof == 8)
    {
        const U =
            ulong.max;


        const twoTo64 =
            makeSignedWide(
                false,
                Cent(
                    lo: 0,
                    hi: 1
                )
            );


        assert(
            boundedLinearEquation(
                makeSignedWord(
                    false,
                    U
                ),
                makeSignedWord(
                    false,
                    1
                ),
                twoTo64,
                2,
                2
            )
            == DiophantineStatus.hasSolution
        );


        /*
         * Signed mirror.
         */
        assert(
            boundedLinearEquation(
                makeSignedWord(
                    true,
                    U
                ),
                makeSignedWord(
                    true,
                    1
                ),
                negateWide(twoTo64),
                2,
                2
            )
            == DiophantineStatus.hasSolution
        );


        /*
         * Large modular inverse / near-U² intermediate:
         *
         *     (U-1)*(U-1) - U*(U-2) = 1
         *
         * Both coordinates fit the maximum finite size_t domain:
         *
         *     count = U
         *     max index = U-1
         */
        assert(
            boundedLinearEquation(
                makeSignedWord(
                    false,
                    U - 1
                ),
                makeSignedWord(
                    true,
                    U
                ),
                fromLong(1),
                size_t.max,
                size_t.max
            )
            == DiophantineStatus.hasSolution
        );


        /*
         * Similar full-width case with no bounded solution.
         */
        assert(
            boundedLinearEquation(
                makeSignedWord(
                    false,
                    U
                ),
                makeSignedWord(
                    false,
                    2
                ),
                twoTo64,
                2,
                2
            )
            == DiophantineStatus.noSolution
        );


        /*
         * Maximum legal coordinate for count=size_t.max.
         */
        const maximumLegalCoordinate =
            makeSignedWide(
                false,
                u128(
                    U - 1
                )
            );


        assert(
            boundedLinearEquation(
                makeSignedWord(
                    false,
                    1
                ),
                makeSignedWord(
                    false,
                    0
                ),
                maximumLegalCoordinate,
                size_t.max,
                1
            )
            == DiophantineStatus.hasSolution
        );


        /*
         * U is one beyond the maximum legal coordinate because a count of U
         * has maximum index U-1.
         */
        const oneBeyond =
            makeSignedWide(
                false,
                u128(U)
            );


        assert(
            boundedLinearEquation(
                makeSignedWord(
                    false,
                    1
                ),
                makeSignedWord(
                    false,
                    0
                ),
                oneBeyond,
                size_t.max,
                1
            )
            == DiophantineStatus.noSolution
        );
    }


    writeln(
        "verifiedCases=",
        verifiedCases
    );

    writeln(
        "bounded wide Diophantine equivalence: PASS"
    );

    writeln(
        "full-width modular cases: PASS"
    );
}
