#include <SDL3/SDL.h>
#include "utils/window.h"


double window_get_scale(SDL_Window *window) {
  float scale = SDL_GetWindowDisplayScale(window);
  return scale > 0.0f ? (double) scale : 1.0;
}


double window_get_pixel_density(SDL_Window *window) {
  float density = SDL_GetWindowPixelDensity(window);
  return density > 0.0f ? (double) density : 1.0;
}
