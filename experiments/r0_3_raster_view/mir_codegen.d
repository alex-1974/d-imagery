module mir_codegen;

import mir_adapter :
    MirUniversalPlane,
    MirCanonicalPlane,
    MirContiguousPlane,
    MirContiguousFlat;


/*
 * Same semantic operation for all three Mir representations.
 *
 * The functions deliberately remain separate and non-inlined so that their
 * generated machine code can be inspected independently.
 */


pragma(mangle, "mir_gain_universal")
pragma(inline, false)
void gainBiasUniversal(
    scope MirUniversalPlane!float plane,
    float gain,
    float bias
)
nothrow
@nogc
{
    foreach (y; 0 .. plane.length!0)
    {
        foreach (x; 0 .. plane.length!1)
        {
            plane[y, x] =
                plane[y, x] * gain + bias;
        }
    }
}


pragma(mangle, "mir_gain_canonical")
pragma(inline, false)
void gainBiasCanonical(
    scope MirCanonicalPlane!float plane,
    float gain,
    float bias
)
nothrow
@nogc
{
    foreach (y; 0 .. plane.length!0)
    {
        foreach (x; 0 .. plane.length!1)
        {
            plane[y, x] =
                plane[y, x] * gain + bias;
        }
    }
}


pragma(mangle, "mir_gain_contiguous")
pragma(inline, false)
void gainBiasContiguous(
    scope MirContiguousPlane!float plane,
    float gain,
    float bias
)
nothrow
@nogc
{
    foreach (y; 0 .. plane.length!0)
    {
        foreach (x; 0 .. plane.length!1)
        {
            plane[y, x] =
                plane[y, x] * gain + bias;
        }
    }
}


/*
 * Fully contiguous Mir slice flattened to one logical dimension.
 *
 * This tests whether the 2D shape can disappear completely from the hot
 * loop once physical contiguity is known.
 */
pragma(mangle, "mir_gain_contiguous_flat")
pragma(inline, false)
void gainBiasContiguousFlat(
    scope MirContiguousFlat!float plane,
    float gain,
    float bias
)
nothrow
@nogc
{
    foreach (i; 0 .. plane.length)
    {
        plane[i] =
            plane[i] * gain + bias;
    }
}


/*
 * Raw-pointer reference.
 *
 * This is not a proposed public API.  It is only the code-generation
 * baseline for checking whether the Mir flattened fast path is effectively
 * zero-cost.
 */
pragma(mangle, "raw_gain_flat")
pragma(inline, false)
void gainBiasRawFlat(
    float* data,
    size_t count,
    float gain,
    float bias
)
nothrow
@nogc
{
    foreach (i; 0 .. count)
    {
        data[i] =
            data[i] * gain + bias;
    }
}
