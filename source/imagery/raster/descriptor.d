/++
    Physical plane metadata for raster storage.

    PlaneDescriptor is intentionally access-neutral. It describes where a
    logical plane starts and how samples are reached, but it does not itself
    grant write permission.

    Ownership and lifetime are handled separately by retained backing/lease
    types.
+/
module imagery.raster.descriptor;


/++
    Physical metadata for one logical raster plane.

    `base` identifies the first sample of the physical plane representation.

    Strides are signed and expressed in elements of the sample type interpreted
    by the RasterView using this descriptor. Resource allocation sizes remain
    byte-based at the backing-storage layer.

    Signed strides permit validated negative traversal where required.
+/
struct PlaneDescriptor
{
    const(void)* base;

    ptrdiff_t rowStrideElements;

    ptrdiff_t sampleStrideElements;
}


unittest
{
    float[16] samples;

    const descriptor = PlaneDescriptor(
        samples.ptr,
        4,
        1
    );

    assert(descriptor.base == samples.ptr);
    assert(descriptor.rowStrideElements == 4);
    assert(descriptor.sampleStrideElements == 1);
}


unittest
{
    ubyte[64] samples;

    const descriptor = PlaneDescriptor(
        samples.ptr,
        -8,
        -1
    );

    assert(descriptor.rowStrideElements == -8);
    assert(descriptor.sampleStrideElements == -1);
}
