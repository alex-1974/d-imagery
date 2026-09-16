module lifetime_negative_return_nested_roi;

import lifetime :
    makeTestLease;

import views :
    MultiPlaneRasterView;


/*
 * MUST FAIL.
 *
 * A nested ROI still ultimately borrows descriptors and backing resources
 * retained by the local RasterLease.
 */
@safe
MultiPlaneRasterView!float escapeNestedRoi(
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

    return roi1.roi(
        5,
        2,
        11,
        7
    );
}
