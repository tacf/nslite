#ifndef NSL_UTILS_WINDOW_H
#define NSL_UTILS_WINDOW_H

#include <SDL3/SDL.h>


// UI sizing: how large content should be drawn in the pixel framebuffer
double window_get_scale(SDL_Window *window);

/* Coordinate conversion: SDL reports events in window points, but we render
   into a pixel-sized surface. Events must be scaled by the pixel density.
   window_get_scale(), "speaks" in desktop content scale, this one does not. */
double window_get_pixel_density(SDL_Window *window);


#endif
