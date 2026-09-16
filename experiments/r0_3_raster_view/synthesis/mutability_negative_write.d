module synthesis.mutability_negative_write;

import synthesis.mutability :
    PlaneDescriptor,
    Region2D,
    makeReadView;


/*
 * MUST FAIL:
 * read-only RasterView must not permit mutation of pixel storage.
 */
@safe
void illegalWrite()
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

    auto view =
        makeReadView!float(
            descriptors[],
            Region2D(
                0,
                0,
                8,
                8
            )
        );

    auto data =
        view.planeBase(0);

    data[0] = 1.0f;
}
