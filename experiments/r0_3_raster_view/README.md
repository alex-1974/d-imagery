# R0.3 Raster View Experiment

This experiment evaluates concrete representations for the d-imagery
kernel-facing raster view.

Candidates will include:

- affine single-base representation;
- per-band `PlaneView` descriptors;
- borrowed descriptor sequences;
- retained descriptor blocks;
- an inline/hybrid representation only if measurements justify it.

The experiment must test both representation capability and generated code.

No candidate becomes part of the public library API merely by appearing in
this experiment.
