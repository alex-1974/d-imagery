/++
    Raster sample-type constraints.

    Raster storage is interpreted as raw externally managed bytes. A sample
    type must therefore be safely loadable and copyable without hidden
    ownership, destruction, or indirection semantics.
+/
module imagery.raster.sample;

import std.traits :
    Unqual,
    hasIndirections;


/++
    Whether T is supported as a raw raster sample representation.

    Supported sample types are:

    - unqualified value types;
    - POD;
    - free of pointer/reference-like indirections.

    This intentionally permits plain numeric types, static arrays of such
    types, and POD pixel structs without indirections.

    It intentionally rejects:

    - void;
    - const/immutable/shared-qualified sample types;
    - pointers;
    - dynamic arrays;
    - classes/references;
    - structs containing indirections;
    - structs with elaborate copy/destruction semantics.

    This trait describes representation safety. It does not imply any
    particular radiometric or pixel-format semantics.
+/
template isRasterSampleType(T)
{
    static if (is(T == void))
    {
        enum isRasterSampleType = false;
    }
    else static if (!is(T == Unqual!T))
    {
        enum isRasterSampleType = false;
    }
    else
    {
        enum isRasterSampleType =
            __traits(isPOD, T)
            && !hasIndirections!T;
    }
}


version (unittest)
{

private
struct PlainRgb
{
    ubyte r;
    ubyte g;
    ubyte b;
}


private
struct PointerSample
{
    ubyte* pointer;
}


private
struct DestructibleSample
{
    ubyte value;

    ~this()
    {
    }
}


static assert(isRasterSampleType!ubyte);
static assert(isRasterSampleType!ushort);
static assert(isRasterSampleType!uint);
static assert(isRasterSampleType!float);
static assert(isRasterSampleType!double);

static assert(isRasterSampleType!(float[4]));
static assert(isRasterSampleType!PlainRgb);

static assert(!isRasterSampleType!void);

static assert(
    !isRasterSampleType!(const ubyte)
);

static assert(
    !isRasterSampleType!(immutable ubyte)
);

static assert(
    !isRasterSampleType!(ubyte*)
);

static assert(
    !isRasterSampleType!(ubyte[])
);

static assert(
    !isRasterSampleType!PointerSample
);

static assert(
    !isRasterSampleType!DestructibleSample
);

} // version (unittest)
