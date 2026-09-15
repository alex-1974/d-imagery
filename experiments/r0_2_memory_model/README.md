# R0.2 Memory Model Experiment

Disposable experiments for evaluating candidate resident-memory view models.

The code in this directory is not part of the d-imagery public API.

Initial comparison:

1. plain contiguous D array;
2. custom pointer/shape/stride view;
3. contiguous `mir.ndslice`;
4. strided/subregion `mir.ndslice`.

The first experiment intentionally uses a simple read reduction.

It tests traversal overhead and optimizer visibility before introducing RGB
layouts, transformations, SIMD, threading or real imagery.

Results must be compared with both DMD and LDC.
