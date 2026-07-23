#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <assert.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#include "lib/nanosvg/nanosvg.h"
#include "lib/nanosvg/nanosvgrast.h"
#include "lib/stb/stb_image.h"
#include "lib/stb/stb_truetype.h"
#include "renderer.h"
#include "utils/utf8.h"

#define MAX_GLYPHSET 256

struct RenImage {
  RenColor *pixels;
  int width, height;
};

typedef struct {
  RenImage *image;
  stbtt_bakedchar glyphs[256];
} GlyphSet;

struct RenFont {
  void *data;
  stbtt_fontinfo stbfont;
  GlyphSet *sets[MAX_GLYPHSET];
  float size;
  int height;
};


static SDL_Window *window;
static struct {
  int left, top, right, bottom;
} clip;


static void *check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}


void ren_init(SDL_Window *win) {
  assert(win);
  window = win;
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  if (surf->format != SDL_PIXELFORMAT_ARGB8888) {
    fprintf(stderr, "Warning: unexpected pixel format %s (expected ARGB8888)\n",
      SDL_GetPixelFormatName(surf->format));
  }
  ren_set_clip_rect((RenRect) { 0, 0, surf->w, surf->h });
}


void ren_update_rects(RenRect *rects, int count) {
  SDL_UpdateWindowSurfaceRects(window, (SDL_Rect *) rects, count);
  static bool initial_frame = true;
  if (initial_frame) {
    SDL_ShowWindow(window);
#if defined(__APPLE__)
    // SDL_ShowWindow does not necessarily launch app in the foreground
    // on macos when launched from the terminal only when the hint is set
    // https://wiki.libsdl.org/SDL3/SDL_HINT_MAC_BACKGROUND_APP
    // instead of setting the hint globally we call RaiseWindow on macos
    SDL_RaiseWindow(window);
#endif
    initial_frame = false;
  }
}


void ren_set_clip_rect(RenRect rect) {
  clip.left = rect.x;
  clip.top = rect.y;
  clip.right = rect.x + rect.width;
  clip.bottom = rect.y + rect.height;
}


void ren_get_size(int *x, int *y) {
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  *x = surf->w;
  *y = surf->h;
}


RenImage *ren_new_image(int width, int height) {
  assert(width > 0 && height > 0);
  size_t pixel_count = (size_t) width * (size_t) height;
  RenImage *image = malloc(sizeof(RenImage) + pixel_count * sizeof(RenColor));
  check_alloc(image);
  image->pixels = (void *) (image + 1);
  image->width = width;
  image->height = height;
  return image;
}


static void convert_rgba_to_ren_colors(RenColor *pixels, size_t count) {
  for (size_t i = 0; i < count; i++) {
    uint8_t red = pixels[i].b;
    pixels[i].b = pixels[i].r;
    pixels[i].r = red;
  }
}


static bool valid_image_size(int width, int height) {
  if (width <= 0 || height <= 0) { return false; }
  size_t maximum_pixels = (SIZE_MAX - sizeof(RenImage)) / sizeof(RenColor);
  return (size_t) width <= maximum_pixels / (size_t) height;
}


static RenImage *load_raster_image(const uint8_t *data, size_t size) {
  if (size > INT_MAX) {
    SDL_SetError("image file is too large");
    return NULL;
  }

  int width, height, channels;
  stbi_uc *rgba = stbi_load_from_memory(data, (int) size, &width, &height,
    &channels, STBI_rgb_alpha);
  if (!rgba) {
    SDL_SetError("unsupported or invalid image: %s", stbi_failure_reason());
    return NULL;
  }
  if (!valid_image_size(width, height)) {
    stbi_image_free(rgba);
    SDL_SetError("image dimensions are too large");
    return NULL;
  }

  RenImage *image = ren_new_image(width, height);
  size_t pixel_count = (size_t) width * (size_t) height;
  memcpy(image->pixels, rgba, pixel_count * sizeof(RenColor));
  stbi_image_free(rgba);
  convert_rgba_to_ren_colors(image->pixels, pixel_count);
  return image;
}


static RenImage *load_svg_image(char *data) {
  NSVGimage *svg = nsvgParse(data, "px", 96.0f);
  if (!svg || svg->width <= 0 || svg->height <= 0
      || svg->width > INT_MAX || svg->height > INT_MAX) {
    nsvgDelete(svg);
    SDL_SetError("unsupported or invalid SVG image");
    return NULL;
  }

  int width = (int) ceilf(svg->width);
  int height = (int) ceilf(svg->height);
  if (!valid_image_size(width, height)) {
    nsvgDelete(svg);
    SDL_SetError("SVG dimensions are too large");
    return NULL;
  }
  NSVGrasterizer *rasterizer = nsvgCreateRasterizer();
  if (!rasterizer) {
    nsvgDelete(svg);
    SDL_SetError("failed to create SVG rasterizer");
    return NULL;
  }

  RenImage *image = ren_new_image(width, height);
  nsvgRasterize(rasterizer, svg, 0, 0, 1, (uint8_t *) image->pixels,
    width, height, width * (int) sizeof(RenColor));
  nsvgDeleteRasterizer(rasterizer);
  nsvgDelete(svg);
  convert_rgba_to_ren_colors(image->pixels, (size_t) width * (size_t) height);
  return image;
}


static bool has_svg_extension(const char *filename) {
  const char *extension = strrchr(filename, '.');
  return extension && SDL_strcasecmp(extension, ".svg") == 0;
}


RenImage *ren_load_image(const char *filename) {
  size_t size;
  uint8_t *data = SDL_LoadFile(filename, &size);
  if (!data) { return NULL; }

  RenImage *image = has_svg_extension(filename)
    ? load_svg_image((char *) data)
    : load_raster_image(data, size);
  SDL_free(data);
  return image;
}


void ren_free_image(RenImage *image) { free(image); }


int ren_get_image_width(RenImage *image) { return image->width; }


int ren_get_image_height(RenImage *image) { return image->height; }


static GlyphSet *load_glyphset(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  /* init image */
  int width = 128;
  int height = 128;
  float s = stbtt_ScaleForMappingEmToPixels(&font->stbfont, 1)
    / stbtt_ScaleForPixelHeight(&font->stbfont, 1);
  int result;
  do {
    set->image = ren_new_image(width, height);
    result = stbtt_BakeFontBitmap(font->data, 0, font->size * s,
      (void *) set->image->pixels, width, height, idx * 256, 256, set->glyphs);

    /* retry with a larger image buffer if the buffer wasn't large enough */
    if (result < 0) {
      width *= 2;
      height *= 2;
      ren_free_image(set->image);
    }
  } while (result < 0);

  /* adjust glyph yoffsets and xadvance */
  int ascent, descent, linegap;
  stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
  float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
  int scaled_ascent = (int) ((float) ascent * scale + 0.5f);
  for (int i = 0; i < 256; i++) {
    set->glyphs[i].yoff += (float) scaled_ascent;
    set->glyphs[i].xadvance = floorf(set->glyphs[i].xadvance);
  }

  /* convert 8bit data to 32bit */
  for (int i = width * height - 1; i >= 0; i--) {
    uint8_t n = *((uint8_t *) set->image->pixels + i);
    set->image->pixels[i] = (RenColor) { .r = 255, .g = 255, .b = 255, .a = n };
  }

  return set;
}


static GlyphSet *get_glyphset(RenFont *font, unsigned codepoint) {
  int idx = (int) ((codepoint >> 8) % MAX_GLYPHSET);
  if (!font->sets[idx]) { font->sets[idx] = load_glyphset(font, idx); }
  return font->sets[idx];
}


RenFont *ren_load_font(const char *filename, float size) {
  /* init font */
  RenFont *font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  /* load font into buffer */
  font->data = SDL_LoadFile(filename, NULL);
  if (!font->data) {
    free(font);
    return NULL;
  }

  /* init stbfont */
  int ok = stbtt_InitFont(&font->stbfont, font->data, 0);
  if (!ok) {
    SDL_free(font->data);
    free(font);
    return NULL;
  }

  /* get height and scale */
  int ascent, descent, linegap;
  stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
  float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, size);
  font->height = (int) ((float) (ascent - descent + linegap) * scale + 0.5f);

  /* make tab and newline glyphs invisible */
  stbtt_bakedchar *g = get_glyphset(font, '\n')->glyphs;
  g['\t'].x1 = g['\t'].x0;
  g['\n'].x1 = g['\n'].x0;

  return font;
}


void ren_free_font(RenFont *font) {
  for (int i = 0; i < MAX_GLYPHSET; i++) {
    GlyphSet *set = font->sets[i];
    if (set) {
      ren_free_image(set->image);
      free(set);
    }
  }
  SDL_free(font->data);
  free(font);
}


void ren_set_font_tab_width(RenFont *font, int n) {
  GlyphSet *set = get_glyphset(font, '\t');
  set->glyphs['\t'].xadvance = (float) n;
}


int ren_get_font_tab_width(RenFont *font) {
  GlyphSet *set = get_glyphset(font, '\t');
  return (int) set->glyphs['\t'].xadvance;
}


int ren_get_font_width(RenFont *font, const char *text) {
  int x = 0;
  const char *p = text;
  const char *end = text + strlen(text);
  uint32_t codepoint;
  while (p < end) {
    p = utf8_decode(p, end, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    stbtt_bakedchar *g = &set->glyphs[codepoint & 0xff];
    x = (int) ((float) x + g->xadvance);
  }
  return x;
}


int ren_get_font_height(RenFont *font) { return font->height; }


static inline RenColor blend_pixel(RenColor dst, RenColor src) {
  int ia = 0xff - src.a;
  dst.r = (uint8_t) ((src.r * src.a + dst.r * ia + 127) / 255);
  dst.g = (uint8_t) ((src.g * src.a + dst.g * ia + 127) / 255);
  dst.b = (uint8_t) ((src.b * src.a + dst.b * ia + 127) / 255);
  return dst;
}


static inline RenColor blend_pixel2(
  RenColor dst, RenColor src, RenColor color) {
  src.a = (uint8_t) ((src.a * color.a + 127) / 255);
  int ia = 0xff - src.a;
  dst.r = (uint8_t) (((src.r * color.r * src.a + 32767) >> 16)
    + ((dst.r * ia + 127) / 255));
  dst.g = (uint8_t) (((src.g * color.g * src.a + 32767) >> 16)
    + ((dst.g * ia + 127) / 255));
  dst.b = (uint8_t) (((src.b * color.b * src.a + 32767) >> 16)
    + ((dst.b * ia + 127) / 255));
  return dst;
}


#define rect_draw_loop(expr)                                                   \
  for (int j = y1; j < y2; j++) {                                              \
    for (int i = x1; i < x2; i++) {                                            \
      *d = expr;                                                               \
      d++;                                                                     \
    }                                                                          \
    d += dr;                                                                   \
  }

void ren_draw_rect(RenRect rect, RenColor color) {
  if (color.a == 0) { return; }

  int x1 = rect.x < clip.left ? clip.left : rect.x;
  int y1 = rect.y < clip.top ? clip.top : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > clip.right ? clip.right : x2;
  y2 = y2 > clip.bottom ? clip.bottom : y2;

  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *d = (RenColor *) surf->pixels;
  d += x1 + y1 * surf->w;
  int dr = surf->w - (x2 - x1);

  if (color.a == 0xff) {
    rect_draw_loop(color);
  } else {
    rect_draw_loop(blend_pixel(*d, color));
  }
}


void ren_draw_image(
  RenImage *image, RenRect *sub, int x, int y, RenColor color) {
  if (color.a == 0) { return; }

  /* clip */
  int n;
  if ((n = clip.left - x) > 0) {
    sub->width -= n;
    sub->x += n;
    x += n;
  }
  if ((n = clip.top - y) > 0) {
    sub->height -= n;
    sub->y += n;
    y += n;
  }
  if ((n = x + sub->width - clip.right) > 0) { sub->width -= n; }
  if ((n = y + sub->height - clip.bottom) > 0) { sub->height -= n; }

  if (sub->width <= 0 || sub->height <= 0) { return; }

  /* draw */
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *s = image->pixels;
  RenColor *d = (RenColor *) surf->pixels;
  s += sub->x + sub->y * image->width;
  d += x + y * surf->w;
  int sr = image->width - sub->width;
  int dr = surf->w - sub->width;

  for (int j = 0; j < sub->height; j++) {
    for (int i = 0; i < sub->width; i++) {
      *d = blend_pixel2(*d, *s, color);
      d++;
      s++;
    }
    d += dr;
    s += sr;
  }
}


void ren_draw_image_scaled(RenImage *image, RenRect rect) {
  if (rect.width <= 0 || rect.height <= 0) { return; }

  int x1 = rect.x < clip.left ? clip.left : rect.x;
  int y1 = rect.y < clip.top ? clip.top : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > clip.right ? clip.right : x2;
  y2 = y2 > clip.bottom ? clip.bottom : y2;
  if (x1 >= x2 || y1 >= y2) { return; }

  SDL_Surface *surface = SDL_GetWindowSurface(window);
  RenColor *destination = (RenColor *) surface->pixels;
  destination += x1 + y1 * surface->w;
  int destination_skip = surface->w - (x2 - x1);

  for (int y = y1; y < y2; y++) {
    int source_y = (int) (((int64_t) (y - rect.y) * image->height)
      / rect.height);
    for (int x = x1; x < x2; x++) {
      int source_x = (int) (((int64_t) (x - rect.x) * image->width)
        / rect.width);
      RenColor source = image->pixels[source_x + source_y * image->width];
      *destination = blend_pixel(*destination, source);
      destination++;
    }
    destination += destination_skip;
  }
}


int ren_draw_text(
  RenFont *font, const char *text, int x, int y, RenColor color) {
  RenRect rect;
  const char *p = text;
  const char *end = text + strlen(text);
  uint32_t codepoint;
  while (p < end) {
    p = utf8_decode(p, end, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    stbtt_bakedchar *g = &set->glyphs[codepoint & 0xff];
    rect.x = g->x0;
    rect.y = g->y0;
    rect.width = g->x1 - g->x0;
    rect.height = g->y1 - g->y0;
    ren_draw_image(set->image, &rect, (int) ((float) x + g->xoff),
      (int) ((float) y + g->yoff), color);
    x = (int) ((float) x + g->xadvance);
  }
  return x;
}
