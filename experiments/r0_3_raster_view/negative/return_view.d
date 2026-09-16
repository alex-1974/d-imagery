module lifetime_negative_return_view;

import lifetime :
    RasterLease,
    makeTestLease;

import views :
    MultiPlaneRasterView;


/*
 * MUST FAIL:
 *
 * The returned RasterView aliases descriptors/resources owned only by the
 * local RasterLease.
 */
@safe
MultiPlaneRasterView!float escapeReturnedView(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    return lease.view();
}
