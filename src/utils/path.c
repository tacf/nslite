#include <SDL3/SDL.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "utils/path.h"


static bool uri_safe_byte(unsigned char byte) {
  return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z')
    || (byte >= '0' && byte <= '9') || byte == '/' || byte == ':' || byte == '-'
    || byte == '.' || byte == '_' || byte == '~';
}


static int hex_value(char digit) {
  if (digit >= '0' && digit <= '9') { return digit - '0'; }
  if (digit >= 'a' && digit <= 'f') { return digit - 'a' + 10; }
  if (digit >= 'A' && digit <= 'F') { return digit - 'A' + 10; }
  return -1;
}


bool path_is_absolute(const char *path) {
  if (!path || !path[0]) { return false; }
  return path[0] == '/' || path[0] == '\\'
    || (path[1] && isalpha((unsigned char) path[0]) && path[1] == ':');
}


char *path_to_file_uri(const char *path) {
  static const char prefix[] = "file://";
  static const char hex[] = "0123456789ABCDEF";
  if (!path) { return NULL; }

  size_t length = sizeof(prefix) - 1;
#ifdef _WIN32
  bool drive_path =
    SDL_strlen(path) >= 2 && isalpha((unsigned char) path[0]) && path[1] == ':';
  if (drive_path) { length++; }
#endif
  for (const unsigned char *p = (const unsigned char *) path; *p; p++) {
    unsigned char byte = *p == '\\' ? '/' : *p;
    size_t encoded_length = uri_safe_byte(byte) ? 1 : 3;
    if (length > SIZE_MAX - encoded_length) { return NULL; }
    length += encoded_length;
  }
  if (length == SIZE_MAX) { return NULL; }

  char *uri = SDL_malloc(length + 1);
  if (!uri) { return NULL; }
  size_t out = 0;
  SDL_memcpy(uri, prefix, sizeof(prefix) - 1);
  out += sizeof(prefix) - 1;
#ifdef _WIN32
  if (drive_path) { uri[out++] = '/'; }
#endif
  for (const unsigned char *p = (const unsigned char *) path; *p; p++) {
    unsigned char byte = *p == '\\' ? '/' : *p;
    if (uri_safe_byte(byte)) {
      uri[out++] = (char) byte;
    } else {
      uri[out++] = '%';
      uri[out++] = hex[byte >> 4];
      uri[out++] = hex[byte & 15];
    }
  }
  uri[out] = '\0';
  return uri;
}


char *file_uri_to_path(const char *uri) {
  static const char prefix[] = "file://";
  if (!uri || SDL_strncmp(uri, prefix, sizeof(prefix) - 1) != 0) {
    return NULL;
  }
  const char *encoded = uri + sizeof(prefix) - 1;
  if (SDL_strncmp(encoded, "localhost/", 10) == 0) { encoded += 9; }
#ifdef _WIN32
  size_t encoded_length = SDL_strlen(encoded);
  if (encoded_length >= 3 && encoded[0] == '/'
    && isalpha((unsigned char) encoded[1]) && encoded[2] == ':') {
    encoded++;
  }
#endif

  size_t length = SDL_strlen(encoded);
  char *path = SDL_malloc(length + 1);
  if (!path) { return NULL; }
  size_t out = 0;
  for (size_t i = 0; i < length; i++) {
    if (encoded[i] != '%') {
      path[out++] = encoded[i];
      continue;
    }
    if (i + 2 >= length) {
      SDL_free(path);
      return NULL;
    }
    int high = hex_value(encoded[i + 1]);
    int low = hex_value(encoded[i + 2]);
    if (high < 0 || low < 0 || (high == 0 && low == 0)) {
      SDL_free(path);
      return NULL;
    }
    path[out++] = (char) (high * 16 + low);
    i += 2;
  }
  path[out] = '\0';
  return path;
}
