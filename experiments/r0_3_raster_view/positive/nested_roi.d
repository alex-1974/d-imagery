module lifetime_nested_roi_positive;

import lifetime :
    makeTestLease;


/*
 * MUST PASS.
 *
 * Multiple ROI transformations must preserve the lifetime relation to the
 * original RasterLease while remaining allocation-free and reusing the same
 * descriptor block.
 */
@safe
void useNestedRoiInsideLease(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    auto view =
        lease.view();

    auto roi1 =
        view.roi(
            4,
            3,
            32,
            20
        );

    auto roi2 =
        roi1.roi(
            5,
            2,
            11,
            7
        );

    assert(roi2.planeCount == 3);

    assert(roi2.width == 11);
    assert(roi2.height == 7);

    /*
     * Absolute origin relative to the original image.
     */
    assert(roi2.originX == 9);
    assert(roi2.originY == 5);

    /*
     * No descriptor rebuilding at either ROI step.
     */
    assert(
        roi1.planes.ptr
        is
        view.planes.ptr
    );

    assert(
        roi2.planes.ptr
        is
        view.planes.ptr
    );
}
