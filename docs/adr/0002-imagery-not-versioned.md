# ADR 0002: Benchmark imagery is not versioned

## Status

Accepted.

## Context

Test imagery may be large, frequently updated and subject to provider-specific
licensing or redistribution restrictions.

The project nevertheless requires reproducible real-world imagery tests.

## Decision

Image data is not stored in Git.

The repository stores reproducible descriptions of test scenes and imagery
sources together with retrieval parameters, provenance and hashes.

Downloaded data is stored locally below `data/`.

## Consequences

A future retrieval tool is required.

Benchmark results must identify the exact locally retrieved imagery by
provenance and content hash.
