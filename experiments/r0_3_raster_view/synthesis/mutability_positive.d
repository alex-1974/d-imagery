module synthesis.mutability_positive;

import synthesis.mutability :
    PlaneDescriptor,
    Region2D,
    RasterView,
    MutableRasterView,
    makeMutableView,
    sharesDescriptorBlock;


@safe
void probe()
{
    /*
     * Heap-backed solely to keep this probe focused on access capability.
     *
     * Descriptor lifetime itself has already been validated separately by
     * the RasterLease/DIP1000 experiments.
     */
    auto storage =
        new float[64];

    auto descriptors =
        new PlaneDescriptor[1];

    descriptors[0] =
        PlaneDescriptor(
            &storage[0],
            8,
            1
        );

    auto mutableView =
        makeMutableView!float(
            descriptors[],
            Region2D(
                0,
                0,
                8,
                8
            )
        );

    static assert(
        is(
            typeof(mutableView)
            ==
            MutableRasterView!float
        )
    );

    auto writable =
        mutableView.planeBase(0);

    static assert(
        is(
            typeof(writable)
            ==
            float*
        )
    );

    writable[0] = 42.0f;

    auto readView =
        mutableView.readOnly();

    static assert(
        is(
            typeof(readView)
            ==
            RasterView!float
        )
    );

    /*
     * Capability downgrade must reuse the exact same descriptor block.
     */
    assert(
        sharesDescriptorBlock(
            mutableView,
            readView
        )
    );

    auto readable =
        readView.planeBase(0);

    static assert(
        is(
            typeof(readable)
            ==
            const(float)*
        )
    );

    assert(readable[0] == 42.0f);

    /*
     * Descriptor block is shared, not rebuilt.
     */
    assert(
        mutableView.planeCount
        ==
        readView.planeCount
    );

    auto mutableRoi =
        mutableView.roi(
            2,
            1,
            3,
            4
        );

    static assert(
        is(
            typeof(mutableRoi)
            ==
            MutableRasterView!float
        )
    );

    assert(
        sharesDescriptorBlock(
            mutableView,
            mutableRoi
        )
    );

    auto downgradedRoi =
        mutableRoi.readOnly();

    static assert(
        is(
            typeof(downgradedRoi)
            ==
            RasterView!float
        )
    );

    assert(
        sharesDescriptorBlock(
            mutableRoi,
            downgradedRoi
        )
    );

    auto readRoi =
        downgradedRoi.roi(
            1,
            1,
            2,
            2
        );

    static assert(
        is(
            typeof(readRoi)
            ==
            RasterView!float
        )
    );

    assert(
        sharesDescriptorBlock(
            downgradedRoi,
            readRoi
        )
    );

    assert(readRoi.region.x == 3);
    assert(readRoi.region.y == 2);
    assert(readRoi.region.width == 2);
    assert(readRoi.region.height == 2);
}
