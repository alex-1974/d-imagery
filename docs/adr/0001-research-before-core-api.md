# ADR 0001: Research before stabilising the core API

## Status

Accepted.

## Context

The performance and scalability of an image engine are strongly affected by
memory layout, stride semantics, processing-region design, caching and execution
strategy.

Prematurely stabilising these abstractions would make later optimisation or
streaming support unnecessarily difficult.

## Decision

The project begins with an explicit R0 research phase.

Raster/view, region/tile/halo and execution APIs are considered experimental
until R0 is complete.

Competing disposable prototypes are encouraged.

## Consequences

Early source compatibility is not a goal.

Architectural choices must be supported by measurements and documented in
subsequent ADRs.
