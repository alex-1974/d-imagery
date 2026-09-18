/++
    Overflow-safe arithmetic for physical byte-address intervals.

    This module deliberately operates on integer addresses rather than
    pointers.

    Converting a validated pointer to this flat address representation remains
    the responsibility of the narrow trusted boundary of the operation that
    owns the pointer.

    Consequently this shared relation classifier itself is fully @safe and
    performs no pointer operations, dereferences, or writes.
+/
module imagery.raster.internal.physical_range;


/++
    Relation between two non-empty physical byte-address intervals.
+/
package(imagery.raster)
enum PhysicalByteRangeRelation : ubyte
{
    overlapping,

    nonOverlapping,

    unrepresentable
}


/++
    Classifies two half-open physical byte-address intervals:

        [firstStart, firstStart + firstByteLength)

        [secondStart, secondStart + secondByteLength)

    Both byte lengths must be non-zero.

    `unrepresentable` is returned when either interval end cannot be represented
    in size_t.

    Integer addresses are used deliberately so the common arithmetic remains
    independent from pointer provenance and pointer conversion.
+/
package(imagery.raster)
PhysicalByteRangeRelation classifyByteAddressRanges(
    size_t firstStart,
    size_t firstByteLength,
    size_t secondStart,
    size_t secondByteLength
)
@safe
pure
nothrow
@nogc
{
    assert(firstByteLength != 0);
    assert(secondByteLength != 0);

    if (
        firstByteLength > size_t.max - firstStart
        || secondByteLength > size_t.max - secondStart
    )
    {
        return PhysicalByteRangeRelation.unrepresentable;
    }

    const firstEnd =
        firstStart + firstByteLength;

    const secondEnd =
        secondStart + secondByteLength;

    if (
        firstEnd <= secondStart
        || secondEnd <= firstStart
    )
    {
        return PhysicalByteRangeRelation.nonOverlapping;
    }

    return PhysicalByteRangeRelation.overlapping;
}


version (unittest)
{

/*
 * Disjoint intervals.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            16,
            4,
            32,
            8
        )
        == PhysicalByteRangeRelation.nonOverlapping
    );
}


/*
 * Half-open intervals that meet exactly at one boundary do not overlap.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            16,
            4,
            20,
            16
        )
        == PhysicalByteRangeRelation.nonOverlapping
    );
}


/*
 * Partial overlap.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            16,
            8,
            20,
            16
        )
        == PhysicalByteRangeRelation.overlapping
    );
}


/*
 * Exact interval equality overlaps.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            16,
            16,
            16,
            16
        )
        == PhysicalByteRangeRelation.overlapping
    );
}


/*
 * Overflow of the first interval end is unrepresentable.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            size_t.max - 1,
            4,
            16,
            4
        )
        == PhysicalByteRangeRelation.unrepresentable
    );
}


/*
 * Overflow of the second interval end is independently detected.
 */
unittest
{
    assert(
        classifyByteAddressRanges(
            16,
            4,
            size_t.max - 1,
            4
        )
        == PhysicalByteRangeRelation.unrepresentable
    );
}

}
