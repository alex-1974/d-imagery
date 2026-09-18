module app;

import mir.ndslice;
import layout_rgb;
import std.algorithm.sorting : sort;
import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln, writeln;

enum WARMUPS = 3;
enum SAMPLES = 24;

struct StridedView2D(T)
{
    T* ptr;
    size_t height;
    size_t width;

    // Distance between two rows, measured in elements.
    size_t rowStride;

    pragma(inline, true)
    ref T opIndex(size_t y, size_t x)
    {
        return ptr[y * rowStride + x];
    }

    pragma(inline, true)
    StridedView2D!T subview(
        size_t y,
        size_t x,
        size_t h,
        size_t w)
    {
        assert(y + h <= height);
        assert(x + w <= width);

        return StridedView2D!T(
            ptr + y * rowStride + x,
            h,
            w,
            rowStride);
    }
}

/* -------------------------------------------------------------------------
 * ubyte traversal baseline
 * ---------------------------------------------------------------------- */

pragma(inline, false)
ulong sumPlain(const(ubyte)[] data)
{
    ulong sum = 0;

    foreach (value; data)
        sum += value;

    return sum;
}

pragma(inline, false)
ulong sumCustom(StridedView2D!ubyte view)
{
    ulong sum = 0;

    foreach (y; 0 .. view.height)
    {
        foreach (x; 0 .. view.width)
            sum += view[y, x];
    }

    return sum;
}

pragma(inline, false)
ulong sumNDSlice(S)(S view, size_t height, size_t width)
{
    ulong sum = 0;

    foreach (y; 0 .. height)
    {
        foreach (x; 0 .. width)
            sum += view[y, x];
    }

    return sum;
}

/* -------------------------------------------------------------------------
 * float point transform
 *
 * Intentionally simple and SIMD-friendly:
 *
 *     dst = src * gain + bias
 *
 * ---------------------------------------------------------------------- */

pragma(inline, false)
float transformPlain(
    const(float)[] src,
    float[] dst,
    float gain,
    float bias)
{
    assert(src.length == dst.length);

    foreach (i; 0 .. src.length)
        dst[i] = src[i] * gain + bias;

    return dst[0] + dst[$ - 1];
}

pragma(inline, false)
float transformCustom(
    StridedView2D!float src,
    StridedView2D!float dst,
    float gain,
    float bias)
{
    assert(src.height == dst.height);
    assert(src.width == dst.width);

    foreach (y; 0 .. src.height)
    {
        foreach (x; 0 .. src.width)
            dst[y, x] = src[y, x] * gain + bias;
    }

    return dst[0, 0] + dst[dst.height - 1, dst.width - 1];
}

pragma(inline, false)
float transformNDSlice(S, D)(
    S src,
    D dst,
    size_t height,
    size_t width,
    float gain,
    float bias)
{
    foreach (y; 0 .. height)
    {
        foreach (x; 0 .. width)
            dst[y, x] = src[y, x] * gain + bias;
    }

    return dst[0, 0] + dst[height - 1, width - 1];
}

pragma(inline, false)
float transformNDSliceFlat(S, D)(
    S src,
    D dst,
    float gain,
    float bias)
{
    assert(src.length == dst.length);

    foreach (i; 0 .. src.length)
        dst[i] = src[i] * gain + bias;

    return dst[0] + dst[$ - 1];
}

/* -------------------------------------------------------------------------
 * Benchmark helpers
 * ---------------------------------------------------------------------- */

void report(
    string name,
    size_t pixels,
    double[] timesMs,
    double checksum)
{
    timesMs.sort;

    const median = timesMs[timesMs.length / 2];

    const p10Index =
        (timesMs.length - 1) * 1 / 10;

    const p90Index =
        (timesMs.length - 1) * 9 / 10;

    const p10 = timesMs[p10Index];
    const p90 = timesMs[p90Index];

    const mpixPerSecond =
        cast(double) pixels /
        (median / 1000.0) /
        1_000_000.0;

    writefln(
        "%-24s median=%8.3f ms  p10=%8.3f  p90=%8.3f  %9.1f MPix/s  checksum=%.3f",
        name,
        median,
        p10,
        p90,
        mpixPerSecond,
        checksum);
}

void benchmarkSum(
    string name,
    size_t pixels,
    int innerIterations,
    ulong delegate() kernel)
{
    foreach (_; 0 .. WARMUPS)
    {
        ulong warmupSink = 0;

        foreach (__; 0 .. innerIterations)
            warmupSink += kernel();

        // Keep the compiler/runtime honest.
        if (warmupSink == ulong.max)
            writeln("unreachable");
    }

    auto times = new double[SAMPLES];
    ulong checksum = 0;

    foreach (sample; 0 .. SAMPLES)
    {
        StopWatch sw;
        sw.start();

        ulong sink = 0;

        foreach (_; 0 .. innerIterations)
            sink += kernel();

        sw.stop();

        checksum ^= sink;

        const totalMs =
            cast(double) sw.peek.total!"nsecs" /
            1_000_000.0;

        times[sample] =
            totalMs / cast(double) innerIterations;
    }

    report(
        name,
        pixels,
        times,
        cast(double) checksum);
}

void benchmarkFloat(
    string name,
    size_t pixels,
    int innerIterations,
    float delegate() kernel)
{
    foreach (_; 0 .. WARMUPS)
    {
        float warmupSink = 0;

        foreach (__; 0 .. innerIterations)
            warmupSink += kernel();

        if (warmupSink == float.infinity)
            writeln("unreachable");
    }

    auto times = new double[SAMPLES];
    double checksum = 0;

    foreach (sample; 0 .. SAMPLES)
    {
        StopWatch sw;
        sw.start();

        float sink = 0;

        foreach (_; 0 .. innerIterations)
            sink += kernel();

        sw.stop();

        checksum += sink;

        const totalMs =
            cast(double) sw.peek.total!"nsecs" /
            1_000_000.0;

        times[sample] =
            totalMs / cast(double) innerIterations;
    }

    report(
        name,
        pixels,
        times,
        checksum);
}


/* -------------------------------------------------------------------------
 * Rotating benchmark groups
 *
 * Candidate order is rotated for every sample so that thermal state,
 * turbo behaviour and scheduler history are not systematically associated
 * with one implementation.
 * ---------------------------------------------------------------------- */

struct SumCase
{
    string name;
    ulong delegate() kernel;
}

void benchmarkSumGroup(
    SumCase[] cases,
    size_t pixels,
    int innerIterations)
{
    double[][] times;
    times.length = cases.length;

    foreach (ref sampleTimes; times)
        sampleTimes.length = SAMPLES;

    ulong[] checksums = new ulong[cases.length];

    // Warm every candidate.
    foreach (warmup; 0 .. WARMUPS)
    {
        foreach (offset; 0 .. cases.length)
        {
            const i =
                (warmup + offset) % cases.length;

            ulong sink = 0;

            foreach (_; 0 .. innerIterations)
                sink += cases[i].kernel();

            if (sink == ulong.max)
                writeln("unreachable");
        }
    }

    // Rotate candidate order for every measured sample.
    foreach (sample; 0 .. SAMPLES)
    {
        foreach (offset; 0 .. cases.length)
        {
            const i =
                (sample + offset) % cases.length;

            StopWatch sw;
            sw.start();

            ulong sink = 0;

            foreach (_; 0 .. innerIterations)
                sink += cases[i].kernel();

            sw.stop();

            checksums[i] += sink;

            times[i][sample] =
                cast(double) sw.peek.total!"nsecs" /
                1_000_000.0 /
                cast(double) innerIterations;
        }
    }

    foreach (i, ref c; cases)
    {
        report(
            c.name,
            pixels,
            times[i],
            cast(double) checksums[i]);
    }
}

struct FloatCase
{
    string name;
    float delegate() kernel;
}

void benchmarkFloatGroup(
    FloatCase[] cases,
    size_t pixels,
    int innerIterations)
{
    double[][] times;
    times.length = cases.length;

    foreach (ref sampleTimes; times)
        sampleTimes.length = SAMPLES;

    double[] checksums = new double[cases.length];
    checksums[] = 0.0;

    /*
     * Warm every candidate equally.
     *
     * Rotate warm-up order as well, although warm-up timings are discarded.
     */
    foreach (warmup; 0 .. WARMUPS)
    {
        foreach (offset; 0 .. cases.length)
        {
            const i =
                (warmup + offset) % cases.length;

            float sink = 0;

            foreach (_; 0 .. innerIterations)
                sink += cases[i].kernel();

            if (sink == float.infinity)
                writeln("unreachable");
        }
    }

    /*
     * Rotate candidate order for each measured sample.
     *
     * Example with four candidates:
     *
     * sample 0: 0 1 2 3
     * sample 1: 1 2 3 0
     * sample 2: 2 3 0 1
     * sample 3: 3 0 1 2
     */
    foreach (sample; 0 .. SAMPLES)
    {
        foreach (offset; 0 .. cases.length)
        {
            const i =
                (sample + offset) % cases.length;

            StopWatch sw;
            sw.start();

            float sink = 0;

            foreach (_; 0 .. innerIterations)
                sink += cases[i].kernel();

            sw.stop();

            checksums[i] += sink;

            times[i][sample] =
                cast(double) sw.peek.total!"nsecs" /
                1_000_000.0 /
                cast(double) innerIterations;
        }
    }

    foreach (i, ref c; cases)
    {
        report(
            c.name,
            pixels,
            times[i],
            checksums[i]);
    }
}

/* -------------------------------------------------------------------------
 * Main
 * ---------------------------------------------------------------------- */

void main()
{
    enum H = 4096;
    enum W = 4096;

    enum ROI_Y = 1024;
    enum ROI_X = 1024;
    enum ROI_H = 2048;
    enum ROI_W = 2048;

    /*
     * The inner repetition count makes one timed sample long enough that
     * timer and scheduler noise are much smaller than before.
     */
    enum SUM_INNER = 24;
    enum TRANSFORM_INNER = 8;
    enum LAYOUT_INNER = 4;

    writeln("imagery-d R0.2 memory-model benchmark");
    writeln("======================================");
    writefln("image:       %s x %s", W, H);
    writefln("ROI:         %s x %s", ROI_W, ROI_H);
    writefln("warmups:     %s", WARMUPS);
    writefln("samples:     %s", SAMPLES);
    writeln;

    /* ------------------------------------------------------------------ */
    /* ubyte traversal                                                    */
    /* ------------------------------------------------------------------ */

    auto storage = new ubyte[H * W];

    foreach (i, ref value; storage)
        value = cast(ubyte)((i * 131 + 17) & 0xff);

    auto custom = StridedView2D!ubyte(
        storage.ptr,
        H,
        W,
        W);

    auto customROI = custom.subview(
        ROI_Y,
        ROI_X,
        ROI_H,
        ROI_W);

    auto nd = storage.sliced(H, W);

    auto ndROI = nd[
        ROI_Y .. ROI_Y + ROI_H,
        ROI_X .. ROI_X + ROI_W];

    const plainFull = sumPlain(storage);
    const customFull = sumCustom(custom);
    const ndFull = sumNDSlice(nd, H, W);

    assert(plainFull == customFull);
    assert(plainFull == ndFull);

    const customROISum = sumCustom(customROI);
    const ndROISum = sumNDSlice(
        ndROI,
        ROI_H,
        ROI_W);

    assert(customROISum == ndROISum);

    writeln("ubyte traversal correctness: PASS");

    writefln(
        "custom view sizeof: %s bytes",
        StridedView2D!ubyte.sizeof);

    writefln(
        "ndslice full sizeof: %s bytes",
        typeof(nd).sizeof);

    writefln(
        "ndslice ROI sizeof:  %s bytes",
        typeof(ndROI).sizeof);

    writeln;
    writeln("ubyte traversal — full image");

    benchmarkSumGroup(
        [
            SumCase(
                "plain contiguous",
                () => sumPlain(storage)),

            SumCase(
                "custom strided",
                () => sumCustom(custom)),

            SumCase(
                "ndslice contiguous",
                () => sumNDSlice(nd, H, W)),
        ],
        H * W,
        SUM_INNER);

    writeln;

    writeln("ubyte traversal — ROI");

    benchmarkSumGroup(
        [
            SumCase(
                "custom ROI",
                () => sumCustom(customROI)),

            SumCase(
                "ndslice ROI",
                () => sumNDSlice(
                    ndROI,
                    ROI_H,
                    ROI_W)),
        ],
        ROI_H * ROI_W,
        SUM_INNER);

    writeln;

    /* ------------------------------------------------------------------ */
    /* float point transform    /* ------------------------------------------------------------------ */
    /* float point transform                                              */
    /* ------------------------------------------------------------------ */

    auto floatSrc = new float[H * W];
    auto floatDstPlain = new float[H * W];
    auto floatDstCustom = new float[H * W];
    auto floatDstND = new float[H * W];

    foreach (i, ref value; floatSrc)
    {
        value =
            cast(float)(i & 1023) /
            1023.0f;
    }

    auto customFloatSrc =
        StridedView2D!float(
            floatSrc.ptr,
            H,
            W,
            W);

    auto customFloatDst =
        StridedView2D!float(
            floatDstCustom.ptr,
            H,
            W,
            W);

    auto customFloatSrcROI =
        customFloatSrc.subview(
            ROI_Y,
            ROI_X,
            ROI_H,
            ROI_W);

    auto customFloatDstROI =
        customFloatDst.subview(
            ROI_Y,
            ROI_X,
            ROI_H,
            ROI_W);

    auto ndFloatSrc =
        floatSrc.sliced(H, W);

    auto ndFloatDst =
        floatDstND.sliced(H, W);

    auto ndFloatSrcFlat =
        ndFloatSrc.flattened;

    auto ndFloatDstFlat =
        ndFloatDst.flattened;

    auto ndFloatSrcROI =
        ndFloatSrc[
            ROI_Y .. ROI_Y + ROI_H,
            ROI_X .. ROI_X + ROI_W];

    auto ndFloatDstROI =
        ndFloatDst[
            ROI_Y .. ROI_Y + ROI_H,
            ROI_X .. ROI_X + ROI_W];

    enum GAIN = 1.125f;
    enum BIAS = 0.03125f;

    const plainProbe =
        transformPlain(
            floatSrc,
            floatDstPlain,
            GAIN,
            BIAS);

    const customProbe =
        transformCustom(
            customFloatSrc,
            customFloatDst,
            GAIN,
            BIAS);

    const ndProbe =
        transformNDSlice(
            ndFloatSrc,
            ndFloatDst,
            H,
            W,
            GAIN,
            BIAS);

    const ndFlatProbe =
        transformNDSliceFlat(
            ndFloatSrcFlat,
            ndFloatDstFlat,
            GAIN,
            BIAS);

    assert(plainProbe == customProbe);
    assert(plainProbe == ndProbe);
    assert(plainProbe == ndFlatProbe);

    const customROIProbe =
        transformCustom(
            customFloatSrcROI,
            customFloatDstROI,
            GAIN,
            BIAS);

    const ndROIProbe =
        transformNDSlice(
            ndFloatSrcROI,
            ndFloatDstROI,
            ROI_H,
            ROI_W,
            GAIN,
            BIAS);

    assert(customROIProbe == ndROIProbe);

    writeln;
    writeln("float point-transform correctness: PASS");

    writeln;
    writeln("float transform — full image");

    benchmarkFloatGroup(
        [
            FloatCase(
                "plain contiguous",
                () => transformPlain(
                    floatSrc,
                    floatDstPlain,
                    GAIN,
                    BIAS)),

            FloatCase(
                "custom strided",
                () => transformCustom(
                    customFloatSrc,
                    customFloatDst,
                    GAIN,
                    BIAS)),

            FloatCase(
                "ndslice contiguous",
                () => transformNDSlice(
                    ndFloatSrc,
                    ndFloatDst,
                    H,
                    W,
                    GAIN,
                    BIAS)),

            FloatCase(
                "ndslice flattened",
                () => transformNDSliceFlat(
                    ndFloatSrcFlat,
                    ndFloatDstFlat,
                    GAIN,
                    BIAS)),
        ],
        H * W,
        TRANSFORM_INNER);

    writeln;
    writeln("float transform — ROI");

    benchmarkFloatGroup(
        [
            FloatCase(
                "custom ROI",
                () => transformCustom(
                    customFloatSrcROI,
                    customFloatDstROI,
                    GAIN,
                    BIAS)),

            FloatCase(
                "ndslice ROI",
                () => transformNDSlice(
                    ndFloatSrcROI,
                    ndFloatDstROI,
                    ROI_H,
                    ROI_W,
                    GAIN,
                    BIAS)),
        ],
        ROI_H * ROI_W,
        TRANSFORM_INNER);

    /* ------------------------------------------------------------------ */
    /* RGB channel-layout experiment                                     */
    /* ------------------------------------------------------------------ */

    writeln;
    writeln("RGB layout — float RGB -> grayscale");

    enum PIXELS = H * W;

    auto rgbInterleaved =
        new float[PIXELS * 3];

    auto rgbRed =
        new float[PIXELS];

    auto rgbGreen =
        new float[PIXELS];

    auto rgbBlue =
        new float[PIXELS];

    auto grayInterleaved =
        new float[PIXELS];

    auto grayPlanar =
        new float[PIXELS];

    /*
     * Materialize exactly the same logical image in both layouts.
     *
     * Initialization is outside the timed region.
     */
    foreach (i; 0 .. PIXELS)
    {
        const r =
            cast(float)((i * 17 + 3) & 1023) /
            1023.0f;

        const g =
            cast(float)((i * 29 + 7) & 1023) /
            1023.0f;

        const b =
            cast(float)((i * 43 + 11) & 1023) /
            1023.0f;

        const base = i * 3;

        rgbInterleaved[base]     = r;
        rgbInterleaved[base + 1] = g;
        rgbInterleaved[base + 2] = b;

        rgbRed[i]   = r;
        rgbGreen[i] = g;
        rgbBlue[i]  = b;
    }

    const interleavedProbe =
        rgbToGrayInterleaved(
            rgbInterleaved,
            grayInterleaved);

    const planarProbe =
        rgbToGrayPlanar(
            rgbRed,
            rgbGreen,
            rgbBlue,
            grayPlanar);

    assert(interleavedProbe == planarProbe);
    assert(grayInterleaved == grayPlanar);

    writeln("RGB -> grayscale correctness: PASS");

    const sourceBytesPerLayout =
        cast(double)(PIXELS * 3 * float.sizeof);

    const outputBytesPerLayout =
        cast(double)(PIXELS * float.sizeof);

    writefln(
        "source per layout: %.1f MiB",
        sourceBytesPerLayout /
            (1024.0 * 1024.0));

    writefln(
        "output per layout: %.1f MiB",
        outputBytesPerLayout /
            (1024.0 * 1024.0));

    writefln(
        "experiment resident data: %.1f MiB",
        (2.0 * sourceBytesPerLayout +
         2.0 * outputBytesPerLayout) /
            (1024.0 * 1024.0));

    benchmarkFloatGroup(
        [
            FloatCase(
                "RGB interleaved",
                () => rgbToGrayInterleaved(
                    rgbInterleaved,
                    grayInterleaved)),

            FloatCase(
                "RGB planar",
                () => rgbToGrayPlanar(
                    rgbRed,
                    rgbGreen,
                    rgbBlue,
                    grayPlanar)),
        ],
        PIXELS,
        LAYOUT_INNER);


    /* ------------------------------------------------------------------ */
    /* RGB channel extraction                                             */
    /* ------------------------------------------------------------------ */

    writeln;
    writeln("RGB layout — green channel extraction");

    const extractInterleavedProbe =
        extractGreenInterleaved(
            rgbInterleaved,
            grayInterleaved);

    const extractPlanarProbe =
        extractGreenPlanar(
            rgbGreen,
            grayPlanar);

    assert(extractInterleavedProbe == extractPlanarProbe);
    assert(grayInterleaved == grayPlanar);

    writeln("green extraction correctness: PASS");

    benchmarkFloatGroup(
        [
            FloatCase(
                "extract G interleaved",
                () => extractGreenInterleaved(
                    rgbInterleaved,
                    grayInterleaved)),

            FloatCase(
                "extract G planar",
                () => extractGreenPlanar(
                    rgbGreen,
                    grayPlanar)),
        ],
        PIXELS,
        LAYOUT_INNER);


    /* ------------------------------------------------------------------ */
    /* RGB per-channel point transform                                    */
    /* ------------------------------------------------------------------ */

    writeln;
    writeln("RGB layout — per-channel gain/bias");

    /*
     * Keep values safely bounded across repeated in-place benchmark calls.
     * Both layouts receive exactly the same operation count.
     */
    enum float RGB_GAIN_R = 1.0001f;
    enum float RGB_GAIN_G = 0.9999f;
    enum float RGB_GAIN_B = 1.0002f;

    enum float RGB_BIAS_R =  0.00001f;
    enum float RGB_BIAS_G = -0.00002f;
    enum float RGB_BIAS_B =  0.000015f;

    const gainInterleavedProbe =
        gainBiasInterleavedInPlace(
            rgbInterleaved,
            RGB_GAIN_R,
            RGB_GAIN_G,
            RGB_GAIN_B,
            RGB_BIAS_R,
            RGB_BIAS_G,
            RGB_BIAS_B);

    const gainPlanarProbe =
        gainBiasPlanarInPlace(
            rgbRed,
            rgbGreen,
            rgbBlue,
            RGB_GAIN_R,
            RGB_GAIN_G,
            RGB_GAIN_B,
            RGB_BIAS_R,
            RGB_BIAS_G,
            RGB_BIAS_B);

    assert(gainInterleavedProbe == gainPlanarProbe);

    foreach (i; 0 .. PIXELS)
    {
        const base = i * 3;

        assert(rgbInterleaved[base] == rgbRed[i]);
        assert(rgbInterleaved[base + 1] == rgbGreen[i]);
        assert(rgbInterleaved[base + 2] == rgbBlue[i]);
    }

    writeln("per-channel gain/bias correctness: PASS");

    benchmarkFloatGroup(
        [
            FloatCase(
                "gain/bias interleaved",
                () => gainBiasInterleavedInPlace(
                    rgbInterleaved,
                    RGB_GAIN_R,
                    RGB_GAIN_G,
                    RGB_GAIN_B,
                    RGB_BIAS_R,
                    RGB_BIAS_G,
                    RGB_BIAS_B)),

            FloatCase(
                "gain/bias planar",
                () => gainBiasPlanarInPlace(
                    rgbRed,
                    rgbGreen,
                    rgbBlue,
                    RGB_GAIN_R,
                    RGB_GAIN_G,
                    RGB_GAIN_B,
                    RGB_BIAS_R,
                    RGB_BIAS_G,
                    RGB_BIAS_B)),
        ],
        PIXELS,
        LAYOUT_INNER);


    /* ------------------------------------------------------------------ */
    /* Uniform RGB component transform                                    */
    /* ------------------------------------------------------------------ */

    writeln;
    writeln("RGB layout — uniform component gain/bias");

    enum float UNIFORM_GAIN = 1.0001f;
    enum float UNIFORM_BIAS = 0.00001f;

    const uniformInterleavedProbe =
        uniformGainBiasInterleavedInPlace(
            rgbInterleaved,
            UNIFORM_GAIN,
            UNIFORM_BIAS);

    const uniformPlanarProbe =
        uniformGainBiasPlanarInPlace(
            rgbRed,
            rgbGreen,
            rgbBlue,
            UNIFORM_GAIN,
            UNIFORM_BIAS);

    assert(uniformInterleavedProbe == uniformPlanarProbe);

    foreach (i; 0 .. PIXELS)
    {
        const base = i * 3;

        assert(rgbInterleaved[base] == rgbRed[i]);
        assert(rgbInterleaved[base + 1] == rgbGreen[i]);
        assert(rgbInterleaved[base + 2] == rgbBlue[i]);
    }

    writeln("uniform gain/bias correctness: PASS");

    benchmarkFloatGroup(
        [
            FloatCase(
                "uniform interleaved",
                () => uniformGainBiasInterleavedInPlace(
                    rgbInterleaved,
                    UNIFORM_GAIN,
                    UNIFORM_BIAS)),

            FloatCase(
                "uniform planar",
                () => uniformGainBiasPlanarInPlace(
                    rgbRed,
                    rgbGreen,
                    rgbBlue,
                    UNIFORM_GAIN,
                    UNIFORM_BIAS)),
        ],
        PIXELS,
        LAYOUT_INNER);


    /* ------------------------------------------------------------------ */
    /* RGB layout conversion                                              */
    /* ------------------------------------------------------------------ */

    writeln;
    writeln("RGB layout — layout conversion");

    const toPlanarProbe =
        interleavedToPlanar(
            rgbInterleaved,
            rgbRed,
            rgbGreen,
            rgbBlue);

    const toInterleavedProbe =
        planarToInterleaved(
            rgbRed,
            rgbGreen,
            rgbBlue,
            rgbInterleaved);

    assert(toPlanarProbe == toInterleavedProbe);

    foreach (i; 0 .. PIXELS)
    {
        const base = i * 3;

        assert(rgbInterleaved[base] == rgbRed[i]);
        assert(rgbInterleaved[base + 1] == rgbGreen[i]);
        assert(rgbInterleaved[base + 2] == rgbBlue[i]);
    }

    writeln("layout conversion correctness: PASS");

    /*
     * Each conversion reads and writes all three float channels:
     *
     *     12 B read + 12 B write = 24 B / pixel
     *
     * Both representations remain logically identical after every
     * iteration, so the two benchmark cases may safely rotate.
     */
    benchmarkFloatGroup(
        [
            FloatCase(
                "interleaved -> planar",
                () => interleavedToPlanar(
                    rgbInterleaved,
                    rgbRed,
                    rgbGreen,
                    rgbBlue)),

            FloatCase(
                "planar -> interleaved",
                () => planarToInterleaved(
                    rgbRed,
                    rgbGreen,
                    rgbBlue,
                    rgbInterleaved)),
        ],
        PIXELS,
        LAYOUT_INNER);

}
