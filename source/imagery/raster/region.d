/++
    Logical two-dimensional raster region geometry.

    Region2D contains geometry only. It does not own storage and does not
    imply that any backing memory exists.

    Coordinates and extents use size_t because they describe logical raster
    geometry. Arithmetic involving absolute extents must remain overflow-safe.
+/
module imagery.raster.region;


/++
    Rectangular logical raster region.

    `x` and `y` identify the region origin in its enclosing logical coordinate
    system. `width` and `height` are extents.

    Empty regions are representable.
+/
struct Region2D
{
    size_t x;
    size_t y;
    size_t width;
    size_t height;


    /++
        Returns true if either extent is zero.
    +/
    bool empty() const
    @safe
    pure
    nothrow
    @nogc
    {
        return width == 0 || height == 0;
    }


    /++
        Returns true when the absolute end coordinates can be represented
        without overflowing size_t.

        This deliberately uses subtraction-based checks instead of unchecked
        `x + width` or `y + height`.
    +/
    bool hasRepresentableExtent() const
    @safe
    pure
    nothrow
    @nogc
    {
        return width <= size_t.max - x
            && height <= size_t.max - y;
    }


    /++
        Tests whether `relative` fits inside this region when `relative.x`
        and `relative.y` are interpreted relative to this region's origin.

        Subtraction-based containment avoids overflow from expressions such as
        `relative.x + relative.width`.
    +/
    bool containsRelative(Region2D relative) const
    @safe
    pure
    nothrow
    @nogc
    {
        if (relative.x > width || relative.y > height)
        {
            return false;
        }

        if (relative.width > width - relative.x)
        {
            return false;
        }

        if (relative.height > height - relative.y)
        {
            return false;
        }

        return true;
    }


    /++
        Resolves a relative child region into the enclosing coordinate system.

        Returns false if the parent extent itself is not representable, if the
        relative child is outside the parent, or if absolute translation would
        overflow.

        On failure `resolved` is reset to Region2D.init.
    +/
    bool tryResolveRelative(
        Region2D relative,
        out Region2D resolved
    ) const
    @safe
    pure
    nothrow
    @nogc
    {
        resolved = Region2D.init;

        if (!hasRepresentableExtent())
        {
            return false;
        }

        if (!containsRelative(relative))
        {
            return false;
        }

        if (relative.x > size_t.max - x)
        {
            return false;
        }

        if (relative.y > size_t.max - y)
        {
            return false;
        }

        resolved = Region2D(
            x + relative.x,
            y + relative.y,
            relative.width,
            relative.height
        );

        return resolved.hasRepresentableExtent();
    }
}


unittest
{
    const region = Region2D(
        100,
        200,
        640,
        480
    );

    assert(!region.empty());
    assert(region.hasRepresentableExtent());

    assert(region.containsRelative(
        Region2D(0, 0, 640, 480)
    ));

    assert(region.containsRelative(
        Region2D(10, 20, 100, 50)
    ));

    assert(!region.containsRelative(
        Region2D(641, 0, 0, 0)
    ));

    assert(!region.containsRelative(
        Region2D(600, 0, 41, 1)
    ));

    assert(!region.containsRelative(
        Region2D(0, 450, 1, 31)
    ));
}


unittest
{
    const parent = Region2D(
        100,
        200,
        640,
        480
    );

    Region2D child;

    assert(parent.tryResolveRelative(
        Region2D(10, 20, 100, 50),
        child
    ));

    assert(child == Region2D(
        110,
        220,
        100,
        50
    ));
}


unittest
{
    const overflowing = Region2D(
        size_t.max,
        0,
        1,
        1
    );

    assert(!overflowing.hasRepresentableExtent());

    Region2D resolved;

    assert(!overflowing.tryResolveRelative(
        Region2D.init,
        resolved
    ));

    assert(resolved == Region2D.init);
}


unittest
{
    const emptyWidth = Region2D(
        10,
        20,
        0,
        5
    );

    const emptyHeight = Region2D(
        10,
        20,
        5,
        0
    );

    assert(emptyWidth.empty());
    assert(emptyHeight.empty());
}
