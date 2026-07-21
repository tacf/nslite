#include <SDL3/SDL.h>
#include "utils/window.h"


double window_get_scale(SDL_Window *window) {
  float scale = SDL_GetWindowDisplayScale(window);
  return scale > 0.0f ? (double) scale : 1.0;
}
