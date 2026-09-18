/++
    Scalar reference kernels for raster sample conversion.

    E5.3a introduces the first different-sample-type pointwise operation:

        ubyte source -> float target

    The initial kernel is deliberately limited to flat Contiguous 1D execution.

    Logical raster shape, execution-layout selection, source/target alias policy,
    and public operation semantics remain dispatcher responsibilities.

    The kernel does defensively validate equal flat element counts before the
    first target write. This is an execution-contract check rather than logical
    two-dimensional shape validation.

    Every ubyte value is exactly representable as float, so this operation
    requires no rounding, clamping, overflow, NaN, or infinity policy.

    Source/target overlap is not part of the E5.3a correctness contract.
+/
module imagery.raster.internal.scalar_conversion;

import mir.ndslice :
    Contiguous,
    Slice;


/++
    Converts one flat contiguous ubyte source into a flat contiguous float
    target.

    Returns false when the flat element counts differ. In that case the target
    is not modified.

    On success each target sample is exactly:

        cast(float) source[i]

    Source/target overlap is intentionally not handled here. A higher operation
    layer must establish any required alias relation before invoking the kernel.
+/
package(imagery.raster)
bool scalarConvertUbyteToFloatContiguous1D(
    scope Slice!(const(ubyte)*, 1, Contiguous) source,
    scope Slice!(float*, 1, Contiguous) target
)
@safe
pure
nothrow
@nogc
{
    if (source.length!0 != target.length!0)
        return false;

    foreach (i; 0 .. source.length!0)
    {
        target[i] =
            cast(float)
                source[i];
    }

    return true;
}


version (unittest)
{

/*
 * The complete ubyte domain converts exactly to float.
 */
unittest
{
    ubyte[256] sourceStorage;
    float[256] targetStorage;

    foreach (i; 0 .. sourceStorage.length)
    {
        sourceStorage[i] =
            cast(ubyte) i;
    }

    auto source =
        Slice!(const(ubyte)*, 1, Contiguous)(
            [
                sourceStorage.length
            ],
            sourceStorage.ptr
        );

    auto target =
        Slice!(float*, 1, Contiguous)(
            [
                targetStorage.length
            ],
            targetStorage.ptr
        );

    assert(
        scalarConvertUbyteToFloatContiguous1D(
            source,
            target
        )
    );

    foreach (i; 0 .. sourceStorage.length)
    {
        assert(
            targetStorage[i]
            == cast(float) sourceStorage[i]
        );
    }

    assert(targetStorage[0] == 0.0f);
    assert(targetStorage[1] == 1.0f);
    assert(targetStorage[127] == 127.0f);
    assert(targetStorage[128] == 128.0f);
    assert(targetStorage[254] == 254.0f);
    assert(targetStorage[255] == 255.0f);
}


/*
 * A shorter target is rejected before the first write.
 */
unittest
{
    ubyte[4] sourceStorage =
        [1, 2, 3, 4];

    float[3] targetStorage =
        [91.0f, 92.0f, 93.0f];

    const expected =
        targetStorage;

    auto source =
        Slice!(const(ubyte)*, 1, Contiguous)(
            [
                sourceStorage.length
            ],
            sourceStorage.ptr
        );

    auto target =
        Slice!(float*, 1, Contiguous)(
            [
                targetStorage.length
            ],
            targetStorage.ptr
        );

    assert(
        !scalarConvertUbyteToFloatContiguous1D(
            source,
            target
        )
    );

    assert(targetStorage == expected);
}


/*
 * A longer target is likewise rejected before the first write.
 */
unittest
{
    ubyte[3] sourceStorage =
        [10, 20, 30];

    float[4] targetStorage =
        [41.0f, 42.0f, 43.0f, 44.0f];

    const expected =
        targetStorage;

    auto source =
        Slice!(const(ubyte)*, 1, Contiguous)(
            [
                sourceStorage.length
            ],
            sourceStorage.ptr
        );

    auto target =
        Slice!(float*, 1, Contiguous)(
            [
                targetStorage.length
            ],
            targetStorage.ptr
        );

    assert(
        !scalarConvertUbyteToFloatContiguous1D(
            source,
            target
        )
    );

    assert(targetStorage == expected);
}


/*
 * Matching empty flat slices form a successful no-op.
 */
unittest
{
    auto source =
        Slice!(const(ubyte)*, 1, Contiguous)(
            [
                cast(size_t) 0
            ],
            cast(const(ubyte)*) null
        );

    auto target =
        Slice!(float*, 1, Contiguous)(
            [
                cast(size_t) 0
            ],
            cast(float*) null
        );

    assert(
        scalarConvertUbyteToFloatContiguous1D(
            source,
            target
        )
    );
}

}
