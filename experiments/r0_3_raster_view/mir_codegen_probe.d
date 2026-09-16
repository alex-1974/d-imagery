module mir_codegen_probe;

import std.stdio : writeln;

import views :
    PlaneDescriptor,
    MultiPlaneRasterView;

import mir_adapter :
    asMirUniversal,
    asMirCanonical,
    asMirContiguous,
    asMirContiguousFlat;

import mir_codegen :
    gainBiasUniversal,
    gainBiasCanonical,
    gainBiasContiguous,
    gainBiasContiguousFlat,
    gainBiasRawFlat;


private
bool approximatelyEqual(
    float a,
    float b
)
nothrow
@nogc
{
    float difference =
        a > b
            ? a - b
            : b - a;

    return difference <= 0.0001f;
}


void main()
{
    enum size_t WIDTH = 257;
    enum size_t HEIGHT = 129;
    enum size_t COUNT = WIDTH * HEIGHT;

    enum float GAIN = 1.25f;
    enum float BIAS = 0.375f;


    auto universalData =
        new float[COUNT];

    auto canonicalData =
        new float[COUNT];

    auto contiguousData =
        new float[COUNT];

    auto flatData =
        new float[COUNT];

    auto rawData =
        new float[COUNT];


    foreach (i; 0 .. COUNT)
    {
        const value =
            cast(float)(i % 997) * 0.03125f;

        universalData[i] = value;
        canonicalData[i] = value;
        contiguousData[i] = value;
        flatData[i] = value;
        rawData[i] = value;
    }


    PlaneDescriptor!float[1]
        universalDescriptor =
    [
        PlaneDescriptor!float(
            universalData.ptr,
            WIDTH,
            1
        )
    ];

    PlaneDescriptor!float[1]
        canonicalDescriptor =
    [
        PlaneDescriptor!float(
            canonicalData.ptr,
            WIDTH,
            1
        )
    ];

    PlaneDescriptor!float[1]
        contiguousDescriptor =
    [
        PlaneDescriptor!float(
            contiguousData.ptr,
            WIDTH,
            1
        )
    ];


    auto universalView =
        MultiPlaneRasterView!float(
            universalDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );

    auto canonicalView =
        MultiPlaneRasterView!float(
            canonicalDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );

    auto contiguousView =
        MultiPlaneRasterView!float(
            contiguousDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );


    /*
     * Same physical layout.
     *
     * Only the Mir slice kind presented to the kernel differs.
     */
    gainBiasUniversal(
        asMirUniversal(
            universalView,
            0
        ),
        GAIN,
        BIAS
    );

    gainBiasCanonical(
        asMirCanonical(
            canonicalView,
            0
        ),
        GAIN,
        BIAS
    );

    gainBiasContiguous(
        asMirContiguous(
            contiguousView,
            0
        ),
        GAIN,
        BIAS
    );


    PlaneDescriptor!float[1]
        flatDescriptor =
    [
        PlaneDescriptor!float(
            flatData.ptr,
            WIDTH,
            1
        )
    ];

    auto flatView =
        MultiPlaneRasterView!float(
            flatDescriptor[],
            WIDTH,
            HEIGHT,
            0,
            0
        );

    gainBiasContiguousFlat(
        asMirContiguousFlat(
            flatView,
            0
        ),
        GAIN,
        BIAS
    );

    gainBiasRawFlat(
        rawData.ptr,
        COUNT,
        GAIN,
        BIAS
    );


    foreach (i; 0 .. COUNT)
    {
        const expected =
            cast(float)(i % 997)
            * 0.03125f
            * GAIN
            + BIAS;

        assert(
            approximatelyEqual(
                universalData[i],
                expected
            )
        );

        assert(
            approximatelyEqual(
                canonicalData[i],
                expected
            )
        );

        assert(
            approximatelyEqual(
                contiguousData[i],
                expected
            )
        );

        assert(
            approximatelyEqual(
                universalData[i],
                canonicalData[i]
            )
        );

        assert(
            approximatelyEqual(
                canonicalData[i],
                contiguousData[i]
            )
        );


        assert(
            approximatelyEqual(
                flatData[i],
                expected
            )
        );

        assert(
            approximatelyEqual(
                rawData[i],
                expected
            )
        );

        assert(
            approximatelyEqual(
                contiguousData[i],
                flatData[i]
            )
        );

        assert(
            approximatelyEqual(
                flatData[i],
                rawData[i]
            )
        );
    }


    writeln(
        "Mir Universal gain/bias correctness: PASS"
    );

    writeln(
        "Mir Canonical gain/bias correctness: PASS"
    );

    writeln(
        "Mir Contiguous gain/bias correctness: PASS"
    );

    writeln(
        "Mir Contiguous flattened correctness: PASS"
    );

    writeln(
        "Raw flat baseline correctness: PASS"
    );

    writeln(
        "R0.3 Mir codegen correctness probe: PASS"
    );
}
