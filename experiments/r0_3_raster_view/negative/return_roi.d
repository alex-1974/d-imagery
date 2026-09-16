module lifetime_negative_return_roi;

import lifetime :
    RasterLease,
    makeTestLease;

import views :
    MultiPlaneRasterView;


/*
 * MUST FAIL:
 *
 * An ROI still aliases the same stable descriptor block and backing
 * resources as its parent view.
 */
@safe
MultiPlaneRasterView!float escapeReturnedRoi(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    auto view =
        lease.view();

    return view.roi(
        1,
        1,
        8,
        8
    );
}
