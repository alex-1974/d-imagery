/++
    Internal Mir adapters for writable raster targets.

    Mir remains an execution substrate. These aliases and adapters are
    package-internal and do not form part of the public imagery-d raster API.
+/
module imagery.raster.internal.mir_target_adapter;

import imagery.raster.internal.target :
    RasterTargetPlane;

import mir.ndslice :
    Contiguous,
    Slice;


/++
    Writable contiguous two-dimensional Mir target.
+/
package(imagery.raster)
alias MirTargetContiguousPlane(T) =
    Slice!(T*, 2, Contiguous);


/++
    Writable flat contiguous Mir target.
+/
package(imagery.raster)
alias MirTargetContiguousFlat(T) =
    Slice!(T*, 1, Contiguous);


/++
    Converts a validated contiguous raster target into a 2D Mir execution
    target.
+/
package(imagery.raster)
MirTargetContiguousPlane!T asMirTargetContiguous(T)(
    return scope RasterTargetPlane!T target
)
@safe
nothrow
@nogc
{
    return MirTargetContiguousPlane!T(
        [
            target.height,
            target.width
        ],
        target.executionBase()
    );
}


/++
    Converts a validated contiguous raster target into a flat Mir execution
    target.
+/
package(imagery.raster)
MirTargetContiguousFlat!T asMirTargetContiguousFlat(T)(
    return scope RasterTargetPlane!T target
)
@safe
nothrow
@nogc
{
    return MirTargetContiguousFlat!T(
        [
            target.elementCount
        ],
        target.executionBase()
    );
}


version (unittest)
{

import imagery.raster.internal.target :
    tryBorrowContiguousTarget;


/*
 * Both writable execution representations alias the borrowed caller storage.
 */
unittest
{
    int[6] storage =
        [0, 1, 2, 3, 4, 5];

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage[],
            3,
            2,
            success
        );

    assert(success);

    auto plane =
        asMirTargetContiguous(
            target
        );

    auto flat =
        asMirTargetContiguousFlat(
            target
        );

    plane[1, 2] = 50;
    assert(storage[5] == 50);

    flat[1] = 10;
    assert(storage[1] == 10);
}


/*
 * Empty targets keep their two-dimensional shape while exposing a null
 * iterator. Flattening yields zero elements.
 */
unittest
{
    int[] storage;

    bool success;

    auto target =
        tryBorrowContiguousTarget(
            storage,
            0,
            7,
            success
        );

    assert(success);

    auto plane =
        asMirTargetContiguous(
            target
        );

    auto flat =
        asMirTargetContiguousFlat(
            target
        );

    assert(plane.length!0 == 7);
    assert(plane.length!1 == 0);

    assert(flat.length!0 == 0);
}

}
