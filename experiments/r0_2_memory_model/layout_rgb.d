module layout_rgb;

/++
    R0.2 RGB memory-layout kernels.

    These kernels intentionally use plain float slices.

    The purpose of this experiment is to compare channel memory layout,
    not view-abstraction overhead. View representation was investigated
    separately in the preceding R0.2 experiments.
+/

enum float GRAY_R = 0.2126f;
enum float GRAY_G = 0.7152f;
enum float GRAY_B = 0.0722f;

/++
    Convert interleaved RGB float pixels to grayscale.

    Source layout:

        RGB RGB RGB RGB ...

    `rgb.length == gray.length * 3`
+/
pragma(inline, false)
float rgbToGrayInterleaved(
    const(float)[] rgb,
    float[] gray)
{
    assert(rgb.length == gray.length * 3);

    foreach (i; 0 .. gray.length)
    {
        const base = i * 3;

        gray[i] =
            rgb[base]     * GRAY_R +
            rgb[base + 1] * GRAY_G +
            rgb[base + 2] * GRAY_B;
    }

    return gray[0] + gray[$ - 1];
}

/++
    Convert planar RGB float pixels to grayscale.

    Source layout:

        RRRR...
        GGGG...
        BBBB...
+/
pragma(inline, false)
float rgbToGrayPlanar(
    const(float)[] red,
    const(float)[] green,
    const(float)[] blue,
    float[] gray)
{
    assert(red.length == gray.length);
    assert(green.length == gray.length);
    assert(blue.length == gray.length);

    foreach (i; 0 .. gray.length)
    {
        gray[i] =
            red[i]   * GRAY_R +
            green[i] * GRAY_G +
            blue[i]  * GRAY_B;
    }

    return gray[0] + gray[$ - 1];
}

/++
    Extract the green channel from interleaved RGB storage.

    Source:

        RGB RGB RGB ...

    Destination:

        GGGG...
+/
pragma(inline, false)
float extractGreenInterleaved(
    const(float)[] rgb,
    float[] greenOut)
{
    assert(rgb.length == greenOut.length * 3);

    foreach (i; 0 .. greenOut.length)
        greenOut[i] = rgb[i * 3 + 1];

    return greenOut[0] + greenOut[$ - 1];
}

/++
    Materialize the green channel from planar storage.

    Source:

        GGGG...

    Destination:

        GGGG...

    Architecturally, planar storage may often expose this plane directly
    without materialization. This kernel deliberately performs a copy so that
    the memory-layout benchmark compares equivalent materialized outputs.
+/
pragma(inline, false)
float extractGreenPlanar(
    const(float)[] green,
    float[] greenOut)
{
    assert(green.length == greenOut.length);

    foreach (i; 0 .. greenOut.length)
        greenOut[i] = green[i];

    return greenOut[0] + greenOut[$ - 1];
}

/++
    Apply independent gain/bias transforms to all three channels of an
    interleaved RGB image, in place.

    Layout:

        RGB RGB RGB ...
+/
pragma(inline, false)
float gainBiasInterleavedInPlace(
    float[] rgb,
    float gainR,
    float gainG,
    float gainB,
    float biasR,
    float biasG,
    float biasB)
{
    assert(rgb.length % 3 == 0);

    for (size_t base = 0; base < rgb.length; base += 3)
    {
        rgb[base] =
            rgb[base] * gainR + biasR;

        rgb[base + 1] =
            rgb[base + 1] * gainG + biasG;

        rgb[base + 2] =
            rgb[base + 2] * gainB + biasB;
    }

    return rgb[0] + rgb[$ - 1];
}

/++
    Apply independent gain/bias transforms to all three channels of a
    planar RGB image, in place.

    Layout:

        RRRR...
        GGGG...
        BBBB...
+/
pragma(inline, false)
float gainBiasPlanarInPlace(
    float[] red,
    float[] green,
    float[] blue,
    float gainR,
    float gainG,
    float gainB,
    float biasR,
    float biasG,
    float biasB)
{
    assert(red.length == green.length);
    assert(red.length == blue.length);

    foreach (i; 0 .. red.length)
    {
        red[i] =
            red[i] * gainR + biasR;

        green[i] =
            green[i] * gainG + biasG;

        blue[i] =
            blue[i] * gainB + biasB;
    }

    return red[0] + blue[$ - 1];
}

/++
    Apply the same gain/bias transform to every RGB component of an
    interleaved image, in place.

    This is intentionally an interleaved-friendly operation: the RGB buffer
    can be treated as one contiguous stream of float components.
+/
pragma(inline, false)
float uniformGainBiasInterleavedInPlace(
    float[] rgb,
    float gain,
    float bias)
{
    foreach (ref value; rgb)
        value = value * gain + bias;

    return rgb[0] + rgb[$ - 1];
}

/++
    Apply the same gain/bias transform to every component of a planar RGB
    image, in place.

    The logical operation is identical to the interleaved variant and touches
    exactly the same number of float components.
+/
pragma(inline, false)
float uniformGainBiasPlanarInPlace(
    float[] red,
    float[] green,
    float[] blue,
    float gain,
    float bias)
{
    assert(red.length == green.length);
    assert(red.length == blue.length);

    foreach (i; 0 .. red.length)
    {
        red[i]   = red[i]   * gain + bias;
        green[i] = green[i] * gain + bias;
        blue[i]  = blue[i]  * gain + bias;
    }

    return red[0] + blue[$ - 1];
}

/++
    Convert an interleaved RGB image to planar RGB storage.

    Source:
        RGB RGB RGB ...

    Destination:
        RRRR...
        GGGG...
        BBBB...
+/
pragma(inline, false)
float interleavedToPlanar(
    const(float)[] rgb,
    float[] red,
    float[] green,
    float[] blue)
{
    assert(rgb.length == red.length * 3);
    assert(red.length == green.length);
    assert(red.length == blue.length);

    foreach (i; 0 .. red.length)
    {
        const base = i * 3;

        red[i]   = rgb[base];
        green[i] = rgb[base + 1];
        blue[i]  = rgb[base + 2];
    }

    return red[0] + blue[$ - 1];
}

/++
    Convert planar RGB storage to an interleaved RGB image.

    Source:
        RRRR...
        GGGG...
        BBBB...

    Destination:
        RGB RGB RGB ...
+/
pragma(inline, false)
float planarToInterleaved(
    const(float)[] red,
    const(float)[] green,
    const(float)[] blue,
    float[] rgb)
{
    assert(red.length == green.length);
    assert(red.length == blue.length);
    assert(rgb.length == red.length * 3);

    foreach (i; 0 .. red.length)
    {
        const base = i * 3;

        rgb[base]     = red[i];
        rgb[base + 1] = green[i];
        rgb[base + 2] = blue[i];
    }

    return rgb[0] + rgb[$ - 1];
}
