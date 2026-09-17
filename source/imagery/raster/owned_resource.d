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

    The caller transfers one complete ResourceEntry release obligation.

    This function can validate structural requirements such as non-null base
    and release function, but it cannot prove releaseContext lifetime or the
    correctness of the external release callback.

    Consequently the boundary remains @system.
+/
package(imagery.raster)
bool tryAdoptResourceEntryAssumeOwned(
    ResourceEntry resource,
    out OwnedByteResource owned
)
@system
nothrow
@nogc
{
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

    The caller must not free or otherwise release `base` after a successful
    call.

    A null base is rejected and no ownership transfer occurs.

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
    out OwnedByteResource owned
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


} // version (unittest)
