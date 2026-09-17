/++
    Internal reduction-policy dispatch for resident raster planes.

    This layer combines two independent facts:

    - requested numeric reduction semantics;
    - execution capabilities derived from the current RasterView.

    It does not define public raster-operation API.

    A requested numeric semantic is never silently replaced by another one.
    In particular, fixedLane4 does not fall back to strict when the current
    plane lacks a compatible execution path.
+/
module imagery.raster.internal.reduction_dispatch;

import imagery.raster.internal.execution_layout :
    PlaneExecutionLayout2D,
    PlaneExecutionTraits;

import imagery.raster.internal.fixed_lane_kernels :
    fixedLane4SumFloatToDoubleContiguous1D;

import imagery.raster.internal.mir_adapter :
    asMirCanonical,
    asMirContiguous,
    asMirContiguousFlat,
    asMirUniversal;

import imagery.raster.internal.scalar_kernels :
    scalarSumCanonical2D,
    scalarSumContiguous1D,
    scalarSumContiguous2D,
    scalarSumUniversal2D;

import imagery.raster.view :
    RasterView;


/++
    Numeric operation graph requested for float-to-double summation.

    `strict` preserves the scalar row-major E3 reduction semantics.

    `fixedLane4` requests the explicit four-lane E4 reduction graph. It is a
    different floating-point semantic, not merely an optimization hint.
+/
package(imagery.raster)
enum SumReductionSemantics : ubyte
{
    strict,

    fixedLane4
}


/++
    Failure category for one package-internal float-to-double sum dispatch.
+/
package(imagery.raster)
enum FloatToDoubleSumDispatchError : ubyte
{
    none,

    invalidPlaneIndex,

    unsupportedExecution,

    invalidSemantics
}


/++
    Result of package-internal float-to-double sum dispatch.

    The default state is deliberately not successful.
+/
package(imagery.raster)
struct FloatToDoubleSumResult
{
    FloatToDoubleSumDispatchError error =
        FloatToDoubleSumDispatchError.invalidSemantics;

    double value = 0.0;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == FloatToDoubleSumDispatchError.none;
    }
}


private
FloatToDoubleSumResult successfulSum(
    double value
)
@safe
pure
nothrow
@nogc
{
    FloatToDoubleSumResult result;

    result.error =
        FloatToDoubleSumDispatchError.none;

    result.value =
        value;

    return result;
}


private
FloatToDoubleSumResult failedSum(
    FloatToDoubleSumDispatchError error
)
@safe
pure
nothrow
@nogc
{
    FloatToDoubleSumResult result;

    result.error =
        error;

    return result;
}


/++
    Dispatch one logical float plane to the execution kernel implementing the
    requested float-to-double reduction semantics.

    Strict semantics are available for every validated execution layout.

    Fixed-lane4 currently requires a flat contiguous execution capability.
    Lack of that capability is reported as unsupportedExecution; dispatch does
    not silently substitute strict semantics.

    Empty valid planes return the additive identity for either supported
    semantic before any execution adapter forms a reachable sample pointer.
+/
package(imagery.raster)
FloatToDoubleSumResult dispatchFloatToDoubleSum(
    scope RasterView!float view,
    size_t planeIndex,
    SumReductionSemantics semantics
)
@safe
nothrow
@nogc
{
    PlaneExecutionTraits traits;

    if (
        !view.tryPlaneExecutionTraits(
            planeIndex,
            traits
        )
    )
    {
        return failedSum(
            FloatToDoubleSumDispatchError.invalidPlaneIndex
        );
    }

    switch (semantics)
    {
        case SumReductionSemantics.strict:
        {
            if (view.empty)
            {
                return successfulSum(0.0);
            }

            final switch (traits.layout2D)
            {
                case PlaneExecutionLayout2D.universal:
                    return successfulSum(
                        scalarSumUniversal2D!double(
                            asMirUniversal(
                                view,
                                planeIndex
                            )
                        )
                    );

                case PlaneExecutionLayout2D.canonical:
                    return successfulSum(
                        scalarSumCanonical2D!double(
                            asMirCanonical(
                                view,
                                planeIndex
                            )
                        )
                    );

                case PlaneExecutionLayout2D.contiguous:
                    if (traits.linearContiguous1D)
                    {
                        return successfulSum(
                            scalarSumContiguous1D!double(
                                asMirContiguousFlat(
                                    view,
                                    planeIndex
                                )
                            )
                        );
                    }

                    return successfulSum(
                        scalarSumContiguous2D!double(
                            asMirContiguous(
                                view,
                                planeIndex
                            )
                        )
                    );
            }
        }

        case SumReductionSemantics.fixedLane4:
        {
            if (view.empty)
            {
                return successfulSum(0.0);
            }

            if (!traits.linearContiguous1D)
            {
                return failedSum(
                    FloatToDoubleSumDispatchError.unsupportedExecution
                );
            }

            return successfulSum(
                fixedLane4SumFloatToDoubleContiguous1D(
                    asMirContiguousFlat(
                        view,
                        planeIndex
                    )
                )
            );
        }

        default:
            return failedSum(
                FloatToDoubleSumDispatchError.invalidSemantics
            );
    }
}


version (unittest)
{

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.region :
    Region2D;

import imagery.raster.view :
    makeRasterViewAssumeValidated;


/*
 * Contiguous cancellation input proves that strict and fixedLane4 are
 * different requested numeric semantics, not two interchangeable fast paths.
 */
unittest
{
    float[4] storage =
    [
        1.0e20f,
        1.0f,
        -1.0e20f,
        1.0f
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    const strict =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.strict
        );

    const fixed =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.fixedLane4
        );

    assert(strict.ok);
    assert(strict.value == 1.0);

    assert(fixed.ok);
    assert(fixed.value == 0.0);
}


/*
 * Canonical padded rows are fully supported by strict semantics but do not
 * currently support the fixed-lane4 graph.
 */
unittest
{
    float[6] storage =
    [
        1.0f,
        2.0f,
        1000.0f,
        3.0f,
        4.0f,
        1000.0f
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            3,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                2,
                2
            )
        );

    const strict =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.strict
        );

    assert(strict.ok);
    assert(strict.value == 10.0);

    const fixed =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.fixedLane4
        );

    assert(!fixed.ok);

    assert(
        fixed.error
        == FloatToDoubleSumDispatchError.unsupportedExecution
    );
}


/*
 * Arbitrary sample stride remains available to strict semantics only.
 */
unittest
{
    float[8] storage =
    [
        1.0f,
        1000.0f,
        2.0f,
        1000.0f,
        3.0f,
        1000.0f,
        4.0f,
        1000.0f
    ];

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            2
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                2,
                2
            )
        );

    const strict =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.strict
        );

    assert(strict.ok);
    assert(strict.value == 10.0);

    const fixed =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.fixedLane4
        );

    assert(!fixed.ok);

    assert(
        fixed.error
        == FloatToDoubleSumDispatchError.unsupportedExecution
    );
}


/*
 * Empty valid planes have the same additive identity for both semantics even
 * though E1 deliberately gives empty views no flat-contiguous capability.
 *
 * Extreme origin/stride metadata also verifies that dispatch does not form a
 * reachable sample pointer before returning the identity.
 */
unittest
{
    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            null,
            ptrdiff_t.min,
            ptrdiff_t.min
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                size_t.max,
                size_t.max,
                0,
                7
            )
        );

    assert(view.empty);

    const strict =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.strict
        );

    const fixed =
        dispatchFloatToDoubleSum(
            view,
            0,
            SumReductionSemantics.fixedLane4
        );

    assert(strict.ok);
    assert(strict.value == 0.0);

    assert(fixed.ok);
    assert(fixed.value == 0.0);
}


/*
 * Plane-index failure is reported before execution dispatch.
 */
unittest
{
    float[4] storage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    const result =
        dispatchFloatToDoubleSum(
            view,
            1,
            SumReductionSemantics.strict
        );

    assert(!result.ok);

    assert(
        result.error
        == FloatToDoubleSumDispatchError.invalidPlaneIndex
    );
}


/*
 * The enum boundary is defensive: arbitrary cast values are rejected rather
 * than being interpreted as one of the defined numeric semantics.
 */
unittest
{
    float[4] storage;

    const PlaneDescriptor[1] descriptors =
    [
        PlaneDescriptor(
            storage.ptr,
            4,
            1
        )
    ];

    auto view =
        makeRasterViewAssumeValidated!float(
            descriptors[],
            Region2D(
                0,
                0,
                4,
                1
            )
        );

    const result =
        dispatchFloatToDoubleSum(
            view,
            0,
            cast(SumReductionSemantics) ubyte.max
        );

    assert(!result.ok);

    assert(
        result.error
        == FloatToDoubleSumDispatchError.invalidSemantics
    );
}

}
