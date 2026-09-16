module bench;

import core.time : MonoTime;
import std.algorithm.sorting : sort;
import std.stdio : writefln, writeln;

import views :
    AffineRGBView,
    PlaneDescriptor,
    MultiPlaneRasterView,
    rgbToGrayAffine,
    rgbToGrayPlanes,
    rgbToGrayAffineInterleaved3,
    rgbToGrayPlanesInterleaved3,
    rgbToGrayPlanesPlanar1;


enum size_t WIDTH = 4096;
enum size_t HEIGHT = 4096;
enum size_t PIXELS = WIDTH * HEIGHT;

enum size_t CANDIDATE_COUNT = 6;
enum size_t WARMUPS = 3;
enum size_t SAMPLES = 24;
enum size_t INNER = 2;


struct BenchmarkState
{
    AffineRGBView!float affine;
    MultiPlaneRasterView!float interleavedPlanes;
    MultiPlaneRasterView!float planarPlanes;

    float[] gray;
}


alias Runner = float function(BenchmarkState*);


pragma(inline, false)
float runDynamicAffine(BenchmarkState* state)
{
    return rgbToGrayAffine(
        state.affine,
        state.gray
    );
}


pragma(inline, false)
float runDynamicPlanesInterleaved(BenchmarkState* state)
{
    return rgbToGrayPlanes(
        state.interleavedPlanes,
        state.gray
    );
}


pragma(inline, false)
float runStaticAffineInterleaved(BenchmarkState* state)
{
    return rgbToGrayAffineInterleaved3(
        state.affine,
        state.gray
    );
}


pragma(inline, false)
float runStaticPlanesInterleaved(BenchmarkState* state)
{
    return rgbToGrayPlanesInterleaved3(
        state.interleavedPlanes,
        state.gray
    );
}


pragma(inline, false)
float runDynamicPlanesPlanar(BenchmarkState* state)
{
    return rgbToGrayPlanes(
        state.planarPlanes,
        state.gray
    );
}


pragma(inline, false)
float runStaticPlanesPlanar(BenchmarkState* state)
{
    return rgbToGrayPlanesPlanar1(
        state.planarPlanes,
        state.gray
    );
}


void fillSources(
    float[] interleaved,
    float[] red,
    float[] green,
    float[] blue
)
{
    foreach (i; 0 .. PIXELS)
    {
        const r =
            cast(float)((i * 17 + 3) & 4095) /
            4095.0f;

        const g =
            cast(float)((i * 29 + 7) & 4095) /
            4095.0f;

        const b =
            cast(float)((i * 43 + 11) & 4095) /
            4095.0f;

        interleaved[i * 3 + 0] = r;
        interleaved[i * 3 + 1] = g;
        interleaved[i * 3 + 2] = b;

        red[i] = r;
        green[i] = g;
        blue[i] = b;
    }
}


double median(double[] values)
{
    auto copy = values.dup;
    sort(copy);

    const n = copy.length;

    if ((n & 1) != 0)
        return copy[n / 2];

    return 0.5 * (
        copy[n / 2 - 1] +
        copy[n / 2]
    );
}


double percentile10(double[] values)
{
    auto copy = values.dup;
    sort(copy);

    const index = (copy.length - 1) / 10;
    return copy[index];
}


double percentile90(double[] values)
{
    auto copy = values.dup;
    sort(copy);

    const index =
        ((copy.length - 1) * 9) / 10;

    return copy[index];
}


void main()
{
    writeln("R0.3 raster-view benchmark");
    writefln(
        "geometry: %sx%s = %s pixels",
        WIDTH,
        HEIGHT,
        PIXELS
    );

    writefln(
        "samples=%s warmups=%s inner=%s",
        SAMPLES,
        WARMUPS,
        INNER
    );

    auto interleaved =
        new float[PIXELS * 3];

    auto red =
        new float[PIXELS];

    auto green =
        new float[PIXELS];

    auto blue =
        new float[PIXELS];

    auto gray =
        new float[PIXELS];

    fillSources(
        interleaved,
        red,
        green,
        blue
    );


    auto affine =
        AffineRGBView!float(
            interleaved.ptr,
            WIDTH,
            HEIGHT,
            WIDTH * 3,
            3,
            1,
            0,
            0
        );


    PlaneDescriptor!float[3]
        interleavedDescriptors =
    [
        PlaneDescriptor!float(
            interleaved.ptr + 0,
            WIDTH * 3,
            3
        ),
        PlaneDescriptor!float(
            interleaved.ptr + 1,
            WIDTH * 3,
            3
        ),
        PlaneDescriptor!float(
            interleaved.ptr + 2,
            WIDTH * 3,
            3
        )
    ];


    auto interleavedPlanes =
        MultiPlaneRasterView!float(
            interleavedDescriptors[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    PlaneDescriptor!float[3]
        planarDescriptors =
    [
        PlaneDescriptor!float(
            red.ptr,
            WIDTH,
            1
        ),
        PlaneDescriptor!float(
            green.ptr,
            WIDTH,
            1
        ),
        PlaneDescriptor!float(
            blue.ptr,
            WIDTH,
            1
        )
    ];


    auto planarPlanes =
        MultiPlaneRasterView!float(
            planarDescriptors[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    auto state =
        BenchmarkState(
            affine,
            interleavedPlanes,
            planarPlanes,
            gray
        );


    Runner[CANDIDATE_COUNT] runners =
    [
        &runDynamicAffine,
        &runDynamicPlanesInterleaved,
        &runStaticAffineInterleaved,
        &runStaticPlanesInterleaved,
        &runDynamicPlanesPlanar,
        &runStaticPlanesPlanar
    ];


    string[CANDIDATE_COUNT] names =
    [
        "dynamic affine / interleaved",
        "dynamic planes / interleaved",
        "static affine / interleaved",
        "static planes / interleaved",
        "dynamic planes / planar",
        "static planes / planar"
    ];


    /*
     * samples[candidate][sample]
     */
    double[][] samples;
    samples.length = CANDIDATE_COUNT;

    foreach (ref candidateSamples; samples)
        candidateSamples.length = SAMPLES;


    /*
     * Warm every implementation before measurement.
     */
    float checksum = 0.0f;

    foreach (_; 0 .. WARMUPS)
    {
        foreach (candidate; 0 .. CANDIDATE_COUNT)
            checksum += runners[candidate](&state);
    }


    /*
     * Rotate order every sample.
     *
     * With 24 samples and 6 candidates every candidate appears
     * equally often at every position in the order.
     */
    foreach (sample; 0 .. SAMPLES)
    {
        foreach (position; 0 .. CANDIDATE_COUNT)
        {
            const candidate =
                (sample + position) %
                CANDIDATE_COUNT;

            const start =
                MonoTime.currTime;

            float localChecksum = 0.0f;

            foreach (_; 0 .. INNER)
            {
                localChecksum +=
                    runners[candidate](&state);
            }

            const elapsed =
                MonoTime.currTime - start;

            const elapsedMs =
                cast(double)
                    elapsed.total!"nsecs" /
                1_000_000.0 /
                INNER;

            samples[candidate][sample] =
                elapsedMs;

            checksum += localChecksum;
        }
    }


    writeln;
    writeln(
        "median ms | p10 | p90 | MPix/s | candidate"
    );

    writeln(
        "--------------------------------------------------------------"
    );


    foreach (candidate; 0 .. CANDIDATE_COUNT)
    {
        const med =
            median(samples[candidate]);

        const p10 =
            percentile10(samples[candidate]);

        const p90 =
            percentile90(samples[candidate]);

        const mpixPerSecond =
            cast(double) PIXELS /
            (med / 1000.0) /
            1_000_000.0;

        writefln(
            "%9.3f | %6.3f | %6.3f | %7.1f | %s",
            med,
            p10,
            p90,
            mpixPerSecond,
            names[candidate]
        );
    }


    writeln;
    writeln("raw samples ms:");

    foreach (candidate; 0 .. CANDIDATE_COUNT)
    {
        writefln("%s:", names[candidate]);

        foreach (sample; 0 .. SAMPLES)
        {
            writefln(
                "  %02s  %.6f",
                sample,
                samples[candidate][sample]
            );
        }
    }

    writeln;
    writefln(
        "checksum guard: %.9f",
        checksum
    );
}
