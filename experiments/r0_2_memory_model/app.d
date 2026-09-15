module app;

import mir.ndslice;
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

    writeln("d-imagery R0.2 memory-model benchmark");
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
}
