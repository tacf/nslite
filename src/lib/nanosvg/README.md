# NanoSVG

Vendored from [memononen/nanosvg](https://github.com/memononen/nanosvg) at
commit
[`239e102`](https://github.com/memononen/nanosvg/commit/239e102ec2c691f2902e20ace2ed36ee4a35cfe6).

The upstream `nanosvg.h` and `nanosvgrast.h` files are unmodified.
`nanosvg.c` is a local implementation wrapper that enables both the parser
and rasterizer implementations.

NSLite parses SVG dimensions in pixels at 96 DPI and rasterizes images at
their intrinsic size.

See `LICENSE.txt` for the upstream zlib-style license.
