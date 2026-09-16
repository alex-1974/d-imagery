module lifetime_negative_global;

import lifetime :
    RasterLease,
    makeTestLease;

import views :
    MultiPlaneRasterView;


/*
 * Ordinary module/TLS global.
 *
 * MUST FAIL:
 *
 * A lease-bound view must not be assignable to global state.
 */
MultiPlaneRasterView!float escapedGlobal;


@safe
void escapeToGlobal(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    escapedGlobal =
        lease.view();
}
