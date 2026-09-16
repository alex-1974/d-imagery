module lifetime_negative_outer_local;

import lifetime :
    RasterLease,
    makeTestLease;

import views :
    MultiPlaneRasterView;


/*
 * MUST FAIL:
 *
 * `escaped` lives beyond the inner RasterLease scope.
 */
@safe
void escapeToOuterLocal(
    size_t* releaseCounters
)
{
    MultiPlaneRasterView!float escaped;

    {
        auto lease =
            makeTestLease(
                releaseCounters
            );

        escaped =
            lease.view();
    }

    auto count =
        escaped.planeCount;

    assert(count == 3);
}
