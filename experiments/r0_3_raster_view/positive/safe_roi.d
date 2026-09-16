module lifetime_safe_roi_positive;

import lifetime :
    makeTestLease;


/*
 * MUST PASS.
 *
 * The ROI remains strictly inside the lifetime of the lease from which its
 * parent view was borrowed.
 */
@safe
void useRoiInsideLease(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    auto view =
        lease.view();

    auto roi =
        view.roi(
            1,
            1,
            8,
            8
        );

    assert(roi.planeCount == 3);
    assert(roi.width == 8);
    assert(roi.height == 8);

    assert(
        roi.planes.ptr
        is
        view.planes.ptr
    );
}
