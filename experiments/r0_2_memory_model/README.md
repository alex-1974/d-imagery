# R0.2 Memory Model Experiment

Disposable experiments for evaluating candidate resident-memory view models.

The code in this directory is not part of the imagery-d public API.

Initial comparison:

1. plain contiguous D array;
2. custom pointer/shape/stride view;
3. contiguous `mir.ndslice`;
4. strided/subregion `mir.ndslice`.

The first experiment intentionally uses a simple read reduction.

The initial phase tests traversal overhead and optimizer visibility before
adding higher-level layout experiments. Later sections extend the same R0.2
experiment with RGB channel layouts, point transformations, and SIMD/codegen
analysis. Threading and real imagery remain outside this experiment.

Results must be compared with both DMD and LDC.

## Channel-layout experiment

The R0.2 experiment also compares float RGB channel layouts:

- interleaved: `RGBRGB...`
- planar: separate R, G and B planes

Kernels cover:

- RGB to grayscale;
- single-channel extraction;
- channel-specific gain/bias;
- channel-uniform gain/bias;
- interleaved/planar conversion.

The results show that layout performance is operation-dependent. Planar storage
is strongly favorable for band-oriented and channel-specific work, while
channel-uniform native AVX2 processing reaches practical parity between the
layouts.

The experiment therefore treats channel layout as explicit raster metadata
rather than selecting one mandatory universal layout.
