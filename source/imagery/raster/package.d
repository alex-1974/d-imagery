/++
    Core raster geometry and physical layout metadata.

    The raster package keeps semantic raster types independent from any
    particular execution substrate such as Mir.
+/
module imagery.raster;

public import imagery.raster.descriptor :
    PlaneDescriptor;

public import imagery.raster.region :
    Region2D;
