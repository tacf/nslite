#include "utils/utf8.h"
#include <stddef.h>
#include <stdint.h>

const char *utf8_decode(
  const char *text, const char *end, uint32_t *codepoint) {
  if (text >= end) {
    *codepoint = 0;
    return end;
  }

  unsigned char first = (unsigned char) text[0];
  if (first < 0x80) {
    *codepoint = first;
    return text + 1;
  }

  size_t width;
  uint32_t value;
  if (first >= 0xc2 && first <= 0xdf) {
    width = 2;
    value = first & 0x1f;
  } else if (first >= 0xe0 && first <= 0xef) {
    width = 3;
    value = first & 0x0f;
  } else if (first >= 0xf0 && first <= 0xf4) {
    width = 4;
    value = first & 0x07;
  } else {
    *codepoint = 0xfffd;
    return text + 1;
  }

  if ((size_t) (end - text) < width) {
    *codepoint = 0xfffd;
    return text + 1;
  }
  for (size_t i = 1; i < width; i++) {
    unsigned char continuation = (unsigned char) text[i];
    if ((continuation & 0xc0) != 0x80) {
      *codepoint = 0xfffd;
      return text + 1;
    }
    value = (value << 6) | (continuation & 0x3f);
  }
  if ((width == 3 && (value < 0x800 || (value >= 0xd800 && value <= 0xdfff)))
    || (width == 4 && (value < 0x10000 || value > 0x10ffff))) {
    *codepoint = 0xfffd;
    return text + 1;
  }
  *codepoint = value;
  return text + width;
}

size_t utf8_utf16_length(const char *text, size_t byte_length) {
  const char *at = text;
  const char *end = text + byte_length;
  size_t units = 0;
  while (at < end) {
    uint32_t codepoint;
    at = utf8_decode(at, end, &codepoint);
    units += codepoint > 0xffff ? 2 : 1;
  }
  return units;
}

size_t utf8_byte_offset_from_utf16(
  const char *text, size_t byte_length, size_t utf16_length) {
  const char *at = text;
  const char *end = text + byte_length;
  size_t units = 0;
  while (at < end && *at != '\n') {
    uint32_t codepoint;
    const char *next = utf8_decode(at, end, &codepoint);
    size_t next_units = units + (codepoint > 0xffff ? 2 : 1);
    if (next_units > utf16_length) { break; }
    at = next;
    units = next_units;
    if (units == utf16_length) { break; }
  }
  return (size_t) (at - text);
}
