module mir_adapter;

import mir.ndslice :
    Slice,
    Universal,
    Canonical,
    Contiguous;

import views :
    MultiPlaneRasterView;


/*
 * Mir is an internal execution substrate.
 *
 * These aliases are intentionally not part of the future public imagery-d
 * API.  They make the experiment's representation choices explicit.
 */
alias MirUniversalPlane(T) =
    Slice!(T*, 2, Universal);

alias MirCanonicalPlane(T) =
    Slice!(T*, 2, Canonical);

alias MirContiguousPlane(T) =
    Slice!(T*, 2, Contiguous);

/*
 * Linear execution view for a plane already proven fully contiguous.
 *
 * This remains an internal kernel representation; RasterView itself keeps
 * its two-dimensional semantic geometry.
 */
alias MirContiguousFlat(T) =
    Slice!(T*, 1, Contiguous);


/*
 * Resolve the first logical sample of a plane inside the current RasterView
 * region.
 *
 * PlaneDescriptor strides are expressed in elements of T, matching the
 * ndslice stride model used by this experiment.
 */
private
T* regionBase(T)(
    return scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@trusted
nothrow
@nogc
{
    assert(planeIndex < view.planeCount);

    auto plane =
        view.planes[planeIndex];

    return plane.base
        + cast(ptrdiff_t)view.originY * plane.rowStride
        + cast(ptrdiff_t)view.originX * plane.sampleStride;
}


/*
 * General adapter.
 *
 * Supports arbitrary row and sample stride representable by Mir Universal.
 *
 * `return scope` preserves the alias relationship between the returned Mir
 * slice and the source RasterView.
 */
MirUniversalPlane!T asMirUniversal(T)(
    return scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@trusted
nothrow
@nogc
{
    assert(planeIndex < view.planeCount);

    const plane =
        view.planes[planeIndex];

    auto base =
        regionBase(
            view,
            planeIndex
        );

    return MirUniversalPlane!T(
        [view.height, view.width],
        [plane.rowStride, plane.sampleStride],
        base
    );
}


/*
 * Canonical adapter.
 *
 * The innermost x dimension must be unit stride.  Rows may still contain
 * padding, and an ROI may therefore remain Canonical without being fully
 * contiguous.
 */
bool canAdaptCanonical(T)(
    scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    assert(planeIndex < view.planeCount);

    return
        view.planes[planeIndex].sampleStride == 1;
}


MirCanonicalPlane!T asMirCanonical(T)(
    return scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@trusted
nothrow
@nogc
{
    assert(canAdaptCanonical(view, planeIndex));

    const plane =
        view.planes[planeIndex];

    auto base =
        regionBase(
            view,
            planeIndex
        );

    return MirCanonicalPlane!T(
        [view.height, view.width],
        [plane.rowStride],
        base
    );
}


/*
 * Fully contiguous adapter.
 *
 * For more than one row, physical row stride must equal the logical region
 * width.  A narrow ROI of a larger contiguous raster therefore does not
 * qualify as fully contiguous.
 *
 * A single-row region is contiguous whenever x samples are unit stride.
 */
bool canAdaptContiguous(T)(
    scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    assert(planeIndex < view.planeCount);

    const plane =
        view.planes[planeIndex];

    if (plane.sampleStride != 1)
        return false;

    return
        view.height <= 1 ||
        plane.rowStride == cast(ptrdiff_t)view.width;
}



/*
 * A contiguous 2D region may be exposed as one linear Slice only when the
 * total logical element count is representable by size_t.
 *
 * In the final core implementation this belongs to the validated RasterView
 * invariants / trusted construction boundary.  Keeping the predicate explicit
 * here prevents the execution adapter from silently overflowing width*height.
 */
bool canAdaptContiguousFlat(T)(
    scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@safe
nothrow
@nogc
{
    if (!canAdaptContiguous(view, planeIndex))
        return false;

    if (view.height == 0)
        return true;

    return
        view.width <= size_t.max / view.height;
}


MirContiguousPlane!T asMirContiguous(T)(
    return scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@trusted
nothrow
@nogc
{
    assert(canAdaptContiguous(view, planeIndex));

    auto base =
        regionBase(
            view,
            planeIndex
        );

    return MirContiguousPlane!T(
        [view.height, view.width],
        base
    );
}



/*
 * One-dimensional fast-path adapter.
 *
 * This is valid only after the complete current region has been proven
 * physically contiguous.
 *
 * No pixel data or descriptor metadata is copied.
 */
MirContiguousFlat!T asMirContiguousFlat(T)(
    return scope MultiPlaneRasterView!T view,
    size_t planeIndex
)
@trusted
nothrow
@nogc
{
    assert(canAdaptContiguousFlat(view, planeIndex));

    auto base =
        regionBase(
            view,
            planeIndex
        );

    const count =
        view.width * view.height;

    return MirContiguousFlat!T(
        [count],
        base
    );
}
