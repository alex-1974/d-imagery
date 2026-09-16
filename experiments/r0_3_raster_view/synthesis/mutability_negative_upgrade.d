module synthesis.mutability_negative_upgrade;

import synthesis.mutability :
    PlaneDescriptor,
    Region2D,
    RasterView,
    MutableRasterView,
    makeReadView;


/*
 * MUST FAIL.
 *
 * A read-only capability must not implicitly become a writable capability.
 *
 * The final production API will additionally keep MutableRasterView
 * construction behind the validated writable lease/backing boundary.
 */
@safe
void illegalUpgrade()
{
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

    RasterView!float readView =
        makeReadView!float(
            descriptors[],
            Region2D(
                0,
                0,
                8,
                8
            )
        );

    MutableRasterView!float writable =
        readView;

    cast(void) writable;
}
