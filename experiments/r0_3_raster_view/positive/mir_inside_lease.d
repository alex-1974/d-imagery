module lifetime_mir_inside_lease_positive;

import lifetime :
    makeTestLease;

import mir_adapter :
    asMirUniversal;


/*
 * MUST PASS.
 *
 * The Mir slice is used only while the originating RasterLease is alive.
 */
@safe
void useMirInsideLease(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    auto view =
        lease.view();

    auto plane =
        asMirUniversal(
            view,
            0
        );

    auto value =
        plane[0, 0];

    cast(void) value;
}
