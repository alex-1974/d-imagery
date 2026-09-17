/++
    Core raster geometry and physical layout metadata.

    The raster package keeps semantic raster types independent from any
    particular execution substrate such as Mir.
+/
module imagery.raster;

public import imagery.raster.sample :
    isRasterSampleType;

public import imagery.raster.owned_resource :
    OwnedByteResource,
    tryAdoptMallocResource;

public import imagery.raster.byte_layout :
    PlaneByteLayout;

public import imagery.raster.import_owned :
    OwnedRasterImportError,
    OwnedRasterImportResult,
    OwnedRasterResourceDisposition,
    tryImportOwnedRaster;

public import imagery.raster.descriptor :
    PlaneDescriptor;

public import imagery.raster.region :
    Region2D;

public import imagery.raster.view :
    RasterView;

public import imagery.raster.backing :
    RasterLease;
