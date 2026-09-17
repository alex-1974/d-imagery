/++
    Public retained ownership token for one physical byte resource.

    OwnedByteResource deliberately hides the raw ResourceEntry representation.

    Public callers may obtain a token only through an explicit ownership
    adoption API. Source-specific adapters may use package-internal raw
    adoption after establishing their own release/context invariants.
+/
module imagery.raster.owned_resource;

import core.stdc.stdlib :
    free;

import imagery.raster.resource :
    ResourceEntry;


/++
    Move-only ownership token for one retained physical byte resource.

    An armed token owns exactly one release obligation.

    Destroying an armed token releases that resource exactly once.

    Moving the token transfers the obligation. A moved-from or relinquished
    token owns nothing.
+/
struct OwnedByteResource
{
private:
    ResourceEntry resource_;

    bool armed_;


    /++
        Releases the currently owned resource, if any.

        This function is trusted because successful construction of an
        OwnedByteResource establishes the invariant that releaseFn and its
        context remain valid for the complete lifetime of the armed token.
    +/
    void releaseIfArmed()
    @trusted
    nothrow
    @nogc
    {
        if (!armed_)
        {
            return;
        }


        /*
         * Disarm before invoking external release code.
         *
         * ReleaseFn is nothrow, but clearing the token first also makes the
         * exact-once state transition explicit.
         */
        auto resource =
            resource_;

        resource_ =
            ResourceEntry.init;

        armed_ =
            false;


        if (
            resource.base !is null
            && resource.releaseFn !is null
        )
        {
            resource.releaseFn(
                resource.releaseContext,
                resource.base,
                resource.byteLength
            );
        }
    }


public:
    @disable this(this);


    /++
        Releases the owned resource exactly once.
    +/
    ~this()
    @trusted
    nothrow
    @nogc
    {
        releaseIfArmed();
    }


    /++
        Whether this token currently owns a physical resource.
    +/
    @property
    bool ownsResource() const
    @safe
    pure
    nothrow
    @nogc
    {
        return armed_;
    }


    /++
        Byte length of the currently owned resource.

        Returns zero for an empty or moved-from token.
    +/
    @property
    size_t byteLength() const
    @safe
    pure
    nothrow
    @nogc
    {
        return armed_
            ? resource_.byteLength
            : 0;
    }


package(imagery.raster):

    /++
        Returns the physical resource base while this token remains armed.

        Package-internal import adapters use this only for checked layout
        conversion before ownership is relinquished.

        The pointer is valid only while this OwnedByteResource continues to own
        the corresponding resource.

        This deliberately remains @system because it exposes a raw physical
        address.
    +/
    @property
    const(void)* resourceBase() const
    @system
    nothrow
    @nogc
    {
        assert(armed_);

        return resource_.base;
    }


    /++
        Transfers the raw release obligation out of this ownership token.

        After this operation the OwnedByteResource is disarmed.

        The caller becomes responsible for ensuring that the returned
        ResourceEntry is either released or transferred into another owner.

        This operation is deliberately package-internal and @system.
    +/
    ResourceEntry relinquishResource()
    @system
    nothrow
    @nogc
    {
        assert(armed_);

        auto result =
            resource_;

        resource_ =
            ResourceEntry.init;

        armed_ =
            false;

        return result;
    }
}


/++
    Package-internal raw ownership-token construction.

    On success the caller transfers one complete ResourceEntry release
    obligation.

    `owned` must be empty. If it is already armed, the function returns false
    without modifying either ownership obligation; the supplied ResourceEntry
    remains caller-owned.

    This function can validate structural requirements such as non-null base
    and release function, but it cannot prove releaseContext lifetime or the
    correctness of the external release callback.

    Consequently the boundary remains @system.
+/
package(imagery.raster)
bool tryAdoptResourceEntryAssumeOwned(
    ResourceEntry resource,
    ref OwnedByteResource owned
)
@system
nothrow
@nogc
{
    /*
     * Ownership adoption never replaces an existing release obligation.
     *
     * In particular this API deliberately uses `ref`, not `out`: D initializes
     * an out argument to T.init on function entry, which is not an acceptable
     * operation for an already armed RAII ownership token.
     */
    if (owned.ownsResource)
    {
        return false;
    }


    if (
        resource.base is null
        || resource.releaseFn is null
    )
    {
        return false;
    }


    owned.resource_ =
        resource;

    owned.armed_ =
        true;

    return true;
}


/++
    Release callback for malloc-compatible allocations.
+/
private
void releaseMallocResource(
    void* context,
    void* base,
    size_t byteLength
)
nothrow
@nogc
{
    if (base !is null)
    {
        free(base);
    }
}


/++
    Adopts one malloc/free-compatible allocation.

    On success ownership of `base` transfers to `owned`.

    `owned` must be empty. Adoption never replaces an existing release
    obligation.

    If `owned` already owns a resource, the function returns false, leaves
    `owned` unchanged, and ownership of `base` remains with the caller.

    The caller must not free or otherwise release `base` after a successful
    call.

    A null base is rejected and no ownership transfer occurs.

    This API deliberately uses a `ref` output target rather than `out`.
    Resetting an already-live ownership token to `.init` would bypass its
    release transition.

    The function is @system because the library cannot prove that:

    - base really denotes a free()-compatible allocation;
    - byteLength correctly describes that allocation;
    - the caller truly owns the allocation being transferred.

    After successful adoption normal OwnedByteResource lifetime management does
    not require raw callback/context handling.
+/
bool tryAdoptMallocResource(
    void* base,
    size_t byteLength,
    ref OwnedByteResource owned
)
@system
nothrow
@nogc
{
    if (base is null)
    {
        return false;
    }


    auto resource =
        ResourceEntry(
            base,
            byteLength,
            null,
            &releaseMallocResource
        );


    return tryAdoptResourceEntryAssumeOwned(
        resource,
        owned
    );
}


version (unittest)
{

import core.stdc.stdlib :
    malloc;

import std.algorithm.mutation :
    move;


private
void releaseCountedResource(
    void* context,
    void* base,
    size_t byteLength
)
nothrow
@nogc
{
    auto releases =
        cast(size_t*) context;

    ++*releases;

    free(base);
}


unittest
{
    OwnedByteResource empty;

    assert(!empty.ownsResource);
    assert(empty.byteLength == 0);
}


unittest
{
    /*
     * Public malloc-compatible adoption.
     */

    void* memory =
        malloc(32);

    assert(memory !is null);


    OwnedByteResource resource;

    assert(
        tryAdoptMallocResource(
            memory,
            32,
            resource
        )
    );

    assert(resource.ownsResource);
    assert(resource.byteLength == 32);

    /*
     * resource destructor owns the corresponding free().
     */
}


unittest
{
    /*
     * Null cannot represent an owned physical resource.
     */

    OwnedByteResource resource;

    assert(
        !tryAdoptMallocResource(
            null,
            16,
            resource
        )
    );

    assert(!resource.ownsResource);
}


unittest
{
    /*
     * Move transfers the exact release obligation.
     */

    size_t releases;

    void* memory =
        malloc(16);

    assert(memory !is null);


    ResourceEntry raw =
        ResourceEntry(
            memory,
            16,
            &releases,
            &releaseCountedResource
        );


    {
        OwnedByteResource first;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                raw,
                first
            )
        );

        assert(first.ownsResource);
        assert(releases == 0);


        auto second =
            move(first);

        assert(!first.ownsResource);
        assert(first.byteLength == 0);

        assert(second.ownsResource);
        assert(second.byteLength == 16);

        assert(releases == 0);
    }


    assert(releases == 1);
}


unittest
{
    /*
     * Relinquishing ownership disarms the token and transfers the raw
     * obligation exactly once.
     */

    size_t releases;

    void* memory =
        malloc(24);

    assert(memory !is null);


    ResourceEntry raw =
        ResourceEntry(
            memory,
            24,
            &releases,
            &releaseCountedResource
        );


    ResourceEntry transferred;


    {
        OwnedByteResource resource;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                raw,
                resource
            )
        );

        assert(resource.ownsResource);


        transferred =
            resource.relinquishResource();

        assert(!resource.ownsResource);
        assert(resource.byteLength == 0);

        assert(releases == 0);
    }


    /*
     * Token destruction did not release after relinquishment.
     */
    assert(releases == 0);


    transferred.releaseFn(
        transferred.releaseContext,
        transferred.base,
        transferred.byteLength
    );

    assert(releases == 1);
}


unittest
{
    /*
     * Raw adoption rejects an incomplete release obligation.
     */

    ubyte sample;

    OwnedByteResource resource;


    assert(
        !tryAdoptResourceEntryAssumeOwned(
            ResourceEntry(
                &sample,
                1,
                null,
                null
            ),
            resource
        )
    );

    assert(!resource.ownsResource);
}


unittest
{
    /*
     * Adoption into an already armed token must fail without replacing or
     * releasing the existing ownership obligation.
     *
     * The candidate resource must remain caller-owned on failure.
     */

    size_t existingReleases;
    size_t candidateReleases;


    void* existingMemory =
        malloc(8);

    void* candidateMemory =
        malloc(12);

    assert(existingMemory !is null);
    assert(candidateMemory !is null);


    ResourceEntry existing =
        ResourceEntry(
            existingMemory,
            8,
            &existingReleases,
            &releaseCountedResource
        );

    ResourceEntry candidate =
        ResourceEntry(
            candidateMemory,
            12,
            &candidateReleases,
            &releaseCountedResource
        );


    {
        OwnedByteResource owned;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                existing,
                owned
            )
        );

        assert(owned.ownsResource);
        assert(owned.byteLength == 8);

        assert(existingReleases == 0);
        assert(candidateReleases == 0);


        /*
         * MUST FAIL transactionally:
         *
         * - existing ownership remains armed;
         * - existing resource is not released;
         * - candidate resource is not adopted or released.
         */
        assert(
            !tryAdoptResourceEntryAssumeOwned(
                candidate,
                owned
            )
        );

        assert(owned.ownsResource);
        assert(owned.byteLength == 8);

        assert(existingReleases == 0);
        assert(candidateReleases == 0);


        /*
         * Candidate remained caller-owned.
         */
        candidate.releaseFn(
            candidate.releaseContext,
            candidate.base,
            candidate.byteLength
        );

        candidate =
            ResourceEntry.init;

        assert(candidateReleases == 1);
        assert(existingReleases == 0);
    }


    /*
     * Existing resource is released exactly once by the token destructor.
     */
    assert(existingReleases == 1);
    assert(candidateReleases == 1);
}


unittest
{
    /*
     * An invalid public adoption attempt must not clear an armed token either.
     */

    size_t releases;

    void* memory =
        malloc(10);

    assert(memory !is null);


    ResourceEntry existing =
        ResourceEntry(
            memory,
            10,
            &releases,
            &releaseCountedResource
        );


    {
        OwnedByteResource owned;

        assert(
            tryAdoptResourceEntryAssumeOwned(
                existing,
                owned
            )
        );

        assert(owned.ownsResource);


        assert(
            !tryAdoptMallocResource(
                null,
                99,
                owned
            )
        );

        assert(owned.ownsResource);
        assert(owned.byteLength == 10);
        assert(releases == 0);
    }


    assert(releases == 1);
}


} // version (unittest)
