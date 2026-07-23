# stb

Vendored from [nothings/stb](https://github.com/nothings/stb).

- `stb_image.h` v2.30 is unmodified from commit
  [`31c1ad3`](https://github.com/nothings/stb/commit/31c1ad37456438565541f4919958214b6e762fb4).
- `stb_truetype.h` v1.24 is from commit
  [`cd74294`](https://github.com/nothings/stb/commit/cd742941e6d70859919ec7f07226be1a06fc7eb8).
  Its code is unmodified; trailing whitespace was removed from two comment
  lines.

The `.c` files are local implementation wrappers:

- `stb_image.c` enables the stb image implementation and disables HDR,
  linear HDR conversion, PIC, PSD, and standard-library file I/O. NSLite
  loads encoded files through SDL and passes their contents to stb_image.
- `stb_truetype.c` enables the stb truetype implementation.

See `LICENSE` for the upstream dual MIT/public-domain terms.
