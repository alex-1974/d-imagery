/++
    Byte-oriented external raster plane layout.

    External libraries and decoders commonly describe raster memory in bytes.

    PlaneByteLayout therefore remains byte-oriented at the import boundary.
    Conversion into the element-oriented PlaneDescriptor representation happens
    only after the sample type is known and the byte representation has been
    validated.
+/
module imagery.raster.byte_layout;

import imagery.raster.descriptor :
    PlaneDescriptor;

import imagery.raster.sample :
    isRasterSampleType;


/++
    Byte-oriented layout of one logical plane inside one physical resource.

    `byteOffset` is relative to the start of the physical resource and
    identifies resident descriptor coordinate `(0, 0)` for this plane.

    Signed byte strides permit validated negative traversal.

    This type contains layout metadata only. It does not own or retain the
    physical resource.
+/
struct PlaneByteLayout
{
    size_t byteOffset;

    ptrdiff_t rowStrideBytes;

    ptrdiff_t sampleStrideBytes;
}


/++
    Failure category while converting byte-oriented external metadata into one
    element-oriented PlaneDescriptor.

    This remains package-internal until the complete public raster-import
    result model is defined.
+/
package(imagery.raster)
enum PlaneByteLayoutConversionError : ubyte
{
    none,

    nullResourceBase,

    invalidResourceRange,

    byteOffsetOutsideResource,

    planeBaseAddressOverflow,

    misalignedPlaneBase,

    sampleSizeNotRepresentable,

    rowStrideNotDivisibleBySampleSize,

    sampleStrideNotDivisibleBySampleSize
}


/++
    Result of one PlaneByteLayout conversion.
+/
package(imagery.raster)
struct PlaneByteLayoutConversionResult
{
    PlaneByteLayoutConversionError error =
        PlaneByteLayoutConversionError.none;


    @property
    bool ok() const
    @safe
    pure
    nothrow
    @nogc
    {
        return error
            == PlaneByteLayoutConversionError.none;
    }
}


/++
    Converts one byte stride into an element stride.

    The source stride is already ptrdiff_t.

    Dividing by a positive sample size cannot increase its magnitude, so an
    exactly divisible byte stride remains representable as ptrdiff_t.

    In particular, this implementation never negates ptrdiff_t.min.
+/
private
bool tryByteStrideToElements(T)(
    ptrdiff_t byteStride,
    out ptrdiff_t elementStride
)
@safe
pure
nothrow
@nogc
{
    elementStride = 0;


    static if (
        T.sizeof
        > cast(size_t) ptrdiff_t.max
    )
    {
        return false;
    }
    else
    {
        enum ptrdiff_t sampleBytes =
            cast(ptrdiff_t) T.sizeof;


        if (
            byteStride % sampleBytes
            != 0
        )
        {
            return false;
        }


        elementStride =
            byteStride / sampleBytes;

        return true;
    }
}


/++
    Converts one external byte-oriented plane layout into the internal
    element-oriented descriptor representation.

    This function performs representation conversion only.

    It does not:

    - adopt or release resource ownership;
    - validate the complete affine region footprint;
    - publish a RasterView;
    - construct a RasterLease.

    The later retained-import adapter will run the existing backing validator
    after all PlaneDescriptors have been constructed.

    The function is package-internal and @system because `resourceBase` is a
    raw external pointer whose allocation validity cannot be proven by this
    conversion layer alone.
+/
package(imagery.raster)
PlaneByteLayoutConversionResult convertPlaneByteLayout(T)(
    const(void)* resourceBase,
    size_t resourceByteLength,
    PlaneByteLayout layout,
    out PlaneDescriptor descriptor
)
@system
nothrow
@nogc
{
    static assert(
        isRasterSampleType!T,
        "Plane byte-layout conversion requires a valid raster sample type."
    );


    descriptor =
        PlaneDescriptor.init;


    if (resourceBase is null)
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.nullResourceBase
        );
    }


    const resourceStart =
        cast(size_t) resourceBase;


    /*
     * Keep address arithmetic explicitly representable.
     *
     * Check the plane address independently so diagnostics remain specific.
     */
    if (
        layout.byteOffset
        > size_t.max - resourceStart
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.planeBaseAddressOverflow
        );
    }


    if (
        resourceByteLength
        > size_t.max - resourceStart
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.invalidResourceRange
        );
    }


    /*
     * Plane descriptor coordinate (0, 0) must identify a byte inside the
     * retained physical resource.
     *
     * One-past-end is deliberately not accepted as a plane base.
     */
    if (
        layout.byteOffset
        >= resourceByteLength
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.byteOffsetOutsideResource
        );
    }


    const planeAddress =
        resourceStart
        + layout.byteOffset;


    if (
        planeAddress
        % T.alignof
        != 0
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.misalignedPlaneBase
        );
    }


    static if (
        T.sizeof
        > cast(size_t) ptrdiff_t.max
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.sampleSizeNotRepresentable
        );
    }


    ptrdiff_t rowStrideElements;

    if (
        !tryByteStrideToElements!T(
            layout.rowStrideBytes,
            rowStrideElements
        )
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.rowStrideNotDivisibleBySampleSize
        );
    }


    ptrdiff_t sampleStrideElements;

    if (
        !tryByteStrideToElements!T(
            layout.sampleStrideBytes,
            sampleStrideElements
        )
    )
    {
        return PlaneByteLayoutConversionResult(
            PlaneByteLayoutConversionError.sampleStrideNotDivisibleBySampleSize
        );
    }


    descriptor =
        PlaneDescriptor(
            cast(const(void)*) planeAddress,
            rowStrideElements,
            sampleStrideElements
        );


    return PlaneByteLayoutConversionResult.init;
}


version (unittest)
{

unittest
{
    /*
     * ubyte interleaved-style plane:
     *
     * byte strides and element strides are identical.
     */

    ubyte[36] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            samples.ptr,
            samples.length,
            PlaneByteLayout(
                1,
                12,
                3
            ),
            descriptor
        );


    assert(result.ok);

    assert(
        descriptor.base
        == samples.ptr + 1
    );

    assert(
        descriptor.rowStrideElements
        == 12
    );

    assert(
        descriptor.sampleStrideElements
        == 3
    );
}


unittest
{
    /*
     * ushort conversion proves byte -> element stride conversion.
     */

    ushort[16] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            samples.ptr,
            samples.sizeof,
            PlaneByteLayout(
                ushort.sizeof,
                8,
                2
            ),
            descriptor
        );


    assert(result.ok);

    assert(
        descriptor.base
        == samples.ptr + 1
    );

    assert(
        descriptor.rowStrideElements
        == 4
    );

    assert(
        descriptor.sampleStrideElements
        == 1
    );
}


unittest
{
    /*
     * Signed negative byte strides convert without any absolute-value step.
     */

    ushort[16] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            samples.ptr,
            samples.sizeof,
            PlaneByteLayout(
                14 * ushort.sizeof,
                -8,
                -2
            ),
            descriptor
        );


    assert(result.ok);

    assert(
        descriptor.base
        == samples.ptr + 14
    );

    assert(
        descriptor.rowStrideElements
        == -4
    );

    assert(
        descriptor.sampleStrideElements
        == -1
    );
}


unittest
{
    /*
     * ptrdiff_t.min must be handled without negating it.
     *
     * ubyte.sizeof == 1, so the converted stride is exactly ptrdiff_t.min.
     */

    ubyte sample;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            &sample,
            1,
            PlaneByteLayout(
                0,
                ptrdiff_t.min,
                0
            ),
            descriptor
        );


    assert(result.ok);

    assert(
        descriptor.rowStrideElements
        == ptrdiff_t.min
    );

    assert(
        descriptor.sampleStrideElements
        == 0
    );
}


unittest
{
    /*
     * ptrdiff_t.min is also safe when exactly divisible by a larger sample.
     */

    ushort sample;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            &sample,
            sample.sizeof,
            PlaneByteLayout(
                0,
                ptrdiff_t.min,
                2
            ),
            descriptor
        );


    assert(result.ok);

    assert(
        descriptor.rowStrideElements
        == ptrdiff_t.min / 2
    );

    assert(
        descriptor.sampleStrideElements
        == 1
    );
}


unittest
{
    ushort[8] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            samples.ptr,
            samples.sizeof,
            PlaneByteLayout(
                0,
                3,
                2
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .rowStrideNotDivisibleBySampleSize
    );

    assert(
        descriptor
        == PlaneDescriptor.init
    );
}


unittest
{
    ushort[8] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            samples.ptr,
            samples.sizeof,
            PlaneByteLayout(
                0,
                4,
                3
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .sampleStrideNotDivisibleBySampleSize
    );

    assert(
        descriptor
        == PlaneDescriptor.init
    );
}


unittest
{
    /*
     * Offset exactly at resourceByteLength is one-past-end and rejected.
     */

    ubyte[8] samples;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            samples.ptr,
            samples.length,
            PlaneByteLayout(
                samples.length,
                1,
                1
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .byteOffsetOutsideResource
    );
}


unittest
{
    /*
     * Misaligned ushort plane base.
     */

    ushort[8] words;

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ushort(
            words.ptr,
            words.sizeof,
            PlaneByteLayout(
                1,
                2,
                2
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .misalignedPlaneBase
    );
}


unittest
{
    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            null,
            1,
            PlaneByteLayout.init,
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .nullResourceBase
    );
}


unittest
{
    /*
     * Synthetic pointer value used only to exercise checked address arithmetic.
     *
     * No dereference occurs.
     */

    const fakeBase =
        cast(const(void)*)(size_t.max - 1);

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            fakeBase,
            1,
            PlaneByteLayout(
                2,
                1,
                1
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .planeBaseAddressOverflow
    );
}


unittest
{
    /*
     * Resource range itself must also be representable.
     *
     * No dereference occurs.
     */

    const fakeBase =
        cast(const(void)*)(size_t.max - 3);

    PlaneDescriptor descriptor;


    const result =
        convertPlaneByteLayout!ubyte(
            fakeBase,
            8,
            PlaneByteLayout(
                0,
                1,
                1
            ),
            descriptor
        );


    assert(
        result.error
        == PlaneByteLayoutConversionError
            .invalidResourceRange
    );
}


} // version (unittest)
