module lifetime_negative_heap;

import lifetime :
    RasterLease,
    makeTestLease;

import views :
    MultiPlaneRasterView;


class Holder
{
    MultiPlaneRasterView!float view;
}


/*
 * MUST FAIL:
 *
 * A lease-bound view must not be stored in an independently living heap
 * object.
 */
@safe
void escapeToHeap(
    size_t* releaseCounters
)
{
    auto holder =
        new Holder;

    auto lease =
        makeTestLease(
            releaseCounters
        );

    holder.view =
        lease.view();
}
