module imagery.raster.internal.fixed_lane_kernels;

import imagery.raster.internal.scalar_kernels :
    scalarSumContiguous1D;

import mir.ndslice :
    Contiguous,
    Slice;


/**
 * Sum a flat contiguous float plane into a double accumulator using the
 * explicit four-lane E4 reduction graph.
 *
 * Numeric semantics:
 *
 *   a0 = x0 + x4 + x8  + ...
 *   a1 = x1 + x5 + x9  + ...
 *   a2 = x2 + x6 + x10 + ...
 *   a3 = x3 + x7 + x11 + ...
 *
 *   total = (a0 + a1) + (a2 + a3)
 *
 * Samples remaining after the last complete four-sample group are appended
 * to `total` in increasing source-index order.
 *
 * This is intentionally not equivalent to the strict left-to-right E3
 * reduction for all floating-point inputs.
 *
 * The specialization is deliberately narrow:
 *
 * - source sample type: float
 * - accumulator/result type: double
 * - source layout: flat Contiguous 1D
 * - fixed lane count: four
 *
 * No fast-math or reassociation compiler attribute is part of this contract.
 */
package(imagery.raster)
double fixedLane4SumFloatToDoubleContiguous1D(
    scope Slice!(const(float)*, 1, Contiguous) plane
)
@safe
pure
nothrow
@nogc
{
    double a0 = 0.0;
    double a1 = 0.0;
    double a2 = 0.0;
    double a3 = 0.0;

    size_t i = 0;

    const size_t length =
        plane.length!0;

    /*
     * Invariant:
     *
     *   i <= length
     *
     * i starts at zero and advances only by four after the condition has
     * established that at least four samples remain.
     */
    while (length - i >= 4)
    {
        a0 +=
            cast(double) plane[i];

        a1 +=
            cast(double) plane[i + 1];

        a2 +=
            cast(double) plane[i + 2];

        a3 +=
            cast(double) plane[i + 3];

        i += 4;
    }

    double total =
        (a0 + a1)
        + (a2 + a3);

    while (i < length)
    {
        total +=
            cast(double) plane[i];

        ++i;
    }

    return total;
}


unittest
{
    float[8] storage =
    [
        1.0f,
        2.0f,
        3.0f,
        4.0f,
        5.0f,
        6.0f,
        7.0f,
        8.0f
    ];

    auto plane =
        Slice!(const(float)*, 1, Contiguous)(
            [storage.length],
            storage.ptr
        );

    assert(
        fixedLane4SumFloatToDoubleContiguous1D(
            plane
        )
        == 36.0
    );
}


unittest
{
    /*
     * This input deliberately distinguishes the strict E3 operation graph
     * from the fixed-lane E4 graph.
     *
     * strict:
     *
     *   (((0 + 1e20) + 1) - 1e20) + 1
     *   -> 1
     *
     * fixed lane 4:
     *
     *   (1e20 + 1) + (-1e20 + 1)
     *   -> 0
     */
    float[4] storage =
    [
        1.0e20f,
        1.0f,
        -1.0e20f,
        1.0f
    ];

    auto plane =
        Slice!(const(float)*, 1, Contiguous)(
            [storage.length],
            storage.ptr
        );

    const double strict =
        scalarSumContiguous1D!double(
            plane
        );

    const double fixed =
        fixedLane4SumFloatToDoubleContiguous1D(
            plane
        );

    assert(strict == 1.0);
    assert(fixed == 0.0);
}


unittest
{
    /*
     * Tail samples are added only after the four lane accumulators have been
     * combined.
     */
    float[5] storage =
    [
        1.0e20f,
        1.0f,
        -1.0e20f,
        1.0f,
        7.0f
    ];

    auto plane =
        Slice!(const(float)*, 1, Contiguous)(
            [storage.length],
            storage.ptr
        );

    assert(
        fixedLane4SumFloatToDoubleContiguous1D(
            plane
        )
        == 7.0
    );
}


unittest
{
    /*
     * Lengths below one complete lane group reduce through the ordered tail.
     */
    float[3] storage =
    [
        1.25f,
        2.5f,
        4.0f
    ];

    auto plane =
        Slice!(const(float)*, 1, Contiguous)(
            [storage.length],
            storage.ptr
        );

    assert(
        fixedLane4SumFloatToDoubleContiguous1D(
            plane
        )
        == 7.75
    );
}


unittest
{
    /*
     * Empty input has the additive identity and must not dereference the
     * iterator.
     */
    auto plane =
        Slice!(const(float)*, 1, Contiguous)(
            [cast(size_t) 0],
            cast(const(float)*) null
        );

    assert(
        fixedLane4SumFloatToDoubleContiguous1D(
            plane
        )
        == 0.0
    );
}
