module lifetime_negative_return_mir_plane;

import lifetime :
    makeTestLease;

import mir_adapter :
    MirUniversalPlane,
    asMirUniversal;


/*
 * MUST FAIL.
 *
 * The Mir slice ultimately aliases resources retained only by the local
 * RasterLease.
 */
@safe
MirUniversalPlane!float escapeMirPlane(
    size_t* releaseCounters
)
{
    auto lease =
        makeTestLease(
            releaseCounters
        );

    auto view =
        lease.view();

    return asMirUniversal(
        view,
        0
    );
}
