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

    A null `releaseFn` is permitted for resources whose lifetime requires no
    explicit release action, for example suitable static storage.
+/
package(imagery.raster)
struct ResourceEntry
{
    void* base;

    size_t byteLength;

    void* releaseContext;

    ReleaseFn releaseFn;
}
