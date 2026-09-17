/++
    Physical retained-resource metadata.

    Resource metadata belongs to the backing-storage layer and therefore uses
    byte addresses and byte lengths.

    It is intentionally package-internal.
+/
module imagery.raster.resource;


/++
    Release callback for one retained physical resource.
+/
package(imagery.raster)
alias ReleaseFn =
    void function(
        void* context,
        void* base,
        size_t byteLength
    )
    nothrow
    @nogc;


/++
    One retained physical resource.

    `base` and `byteLength` describe the byte range retained by RasterBacking.

    `releaseContext` is opaque callback state.

    RasterBacking copies only the pointer value. It does not independently
    retain or copy the object referenced by `releaseContext`.

    Therefore any non-null releaseContext must remain valid until releaseFn is
    invoked. A pointer to caller-local stack state is not valid for a retained
    resource that can outlive that stack frame.

    Establishing that lifetime is part of the raw ownership contract and
    cannot be validated from ResourceEntry metadata alone.

    For dynamically allocated callback state, releaseFn is responsible for any
    required context destruction/deallocation as part of the same release
    obligation.

    A null `releaseFn` is permitted for resources whose lifetime requires no
    explicit release action, for example suitable static storage.

    ResourceEntry remains package-internal. Source-specific adapters must not
    expose this raw callback/context representation as their public API.
+/
package(imagery.raster)
struct ResourceEntry
{
    void* base;

    size_t byteLength;

    void* releaseContext;

    ReleaseFn releaseFn;
}
