#ifndef NSL_UTILS_UTF8_H
#define NSL_UTILS_UTF8_H

#include <stddef.h>
#include <stdint.h>

const char *utf8_decode(const char *text, const char *end, uint32_t *codepoint);
size_t utf8_utf16_length(const char *text, size_t byte_length);
size_t utf8_byte_offset_from_utf16(
  const char *text, size_t byte_length, size_t utf16_length);

#endif
