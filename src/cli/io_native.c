#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

// UTF-8 byte sequence to a single Unicode code point.
// Returns the code point and advances *pos by the number of bytes consumed.
static uint32_t utf8_decode(const unsigned char *buf, int len, int *pos) {
  unsigned char b = buf[*pos];
  uint32_t cp;
  int extra;
  if (b < 0x80) {
    cp = b;
    extra = 0;
  } else if ((b & 0xE0) == 0xC0) {
    cp = b & 0x1F;
    extra = 1;
  } else if ((b & 0xF0) == 0xE0) {
    cp = b & 0x0F;
    extra = 2;
  } else if ((b & 0xF8) == 0xF0) {
    cp = b & 0x07;
    extra = 3;
  } else {
    // Invalid UTF-8 lead byte, use replacement character
    cp = 0xFFFD;
    extra = 0;
  }
  (*pos)++;
  for (int i = 0; i < extra && *pos < len; i++) {
    unsigned char cb = buf[*pos];
    if ((cb & 0xC0) != 0x80) {
      cp = 0xFFFD;
      break;
    }
    cp = (cp << 6) | (cb & 0x3F);
    (*pos)++;
  }
  return cp;
}

// Count the number of UTF-16 code units needed for a UTF-8 buffer.
static int utf8_to_utf16_len(const unsigned char *buf, int byte_len) {
  int pos = 0;
  int utf16_len = 0;
  while (pos < byte_len) {
    uint32_t cp = utf8_decode(buf, byte_len, &pos);
    if (cp > 0xFFFF) {
      utf16_len += 2; // surrogate pair
    } else {
      utf16_len += 1;
    }
  }
  return utf16_len;
}

// Convert UTF-8 buffer to a MoonBit string (UTF-16).
static moonbit_string_t utf8_to_moonbit_string(const unsigned char *buf, int byte_len) {
  int utf16_len = utf8_to_utf16_len(buf, byte_len);
  moonbit_string_t ms = moonbit_make_string(utf16_len, 0);
  int pos = 0;
  int out = 0;
  while (pos < byte_len) {
    uint32_t cp = utf8_decode(buf, byte_len, &pos);
    if (cp > 0xFFFF) {
      // Encode as surrogate pair
      cp -= 0x10000;
      ms[out++] = (uint16_t)(0xD800 + (cp >> 10));
      ms[out++] = (uint16_t)(0xDC00 + (cp & 0x3FF));
    } else {
      ms[out++] = (uint16_t)cp;
    }
  }
  return ms;
}

moonbit_string_t read_stdin(void) {
  size_t capacity = 4096;
  size_t len = 0;
  unsigned char *buf = (unsigned char *)malloc(capacity);
  if (!buf) {
    return moonbit_make_string(0, 0);
  }
  while (1) {
    size_t n = fread(buf + len, 1, capacity - len, stdin);
    len += n;
    if (n == 0) break;
    if (len == capacity) {
      capacity *= 2;
      unsigned char *newbuf = (unsigned char *)realloc(buf, capacity);
      if (!newbuf) {
        free(buf);
        return moonbit_make_string(0, 0);
      }
      buf = newbuf;
    }
  }
  moonbit_string_t result = utf8_to_moonbit_string(buf, (int)len);
  free(buf);
  return result;
}

moonbit_string_t read_file(moonbit_string_t path) {
  // Convert MoonBit string (UTF-16) to C string (UTF-8) for file path
  int path_len = (int)Moonbit_array_length(path);
  // Worst case: 4 bytes per code point
  char *cpath = (char *)malloc(path_len * 4 + 1);
  if (!cpath) {
    return moonbit_make_string(0, 0);
  }
  int out = 0;
  for (int i = 0; i < path_len; i++) {
    uint16_t ch = path[i];
    uint32_t cp;
    // Handle surrogate pairs
    if (ch >= 0xD800 && ch <= 0xDBFF && i + 1 < path_len) {
      uint16_t lo = path[i + 1];
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000 + ((uint32_t)(ch - 0xD800) << 10) + (lo - 0xDC00);
        i++;
      } else {
        cp = ch;
      }
    } else {
      cp = ch;
    }
    // Encode code point as UTF-8
    if (cp < 0x80) {
      cpath[out++] = (char)cp;
    } else if (cp < 0x800) {
      cpath[out++] = (char)(0xC0 | (cp >> 6));
      cpath[out++] = (char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      cpath[out++] = (char)(0xE0 | (cp >> 12));
      cpath[out++] = (char)(0x80 | ((cp >> 6) & 0x3F));
      cpath[out++] = (char)(0x80 | (cp & 0x3F));
    } else {
      cpath[out++] = (char)(0xF0 | (cp >> 18));
      cpath[out++] = (char)(0x80 | ((cp >> 12) & 0x3F));
      cpath[out++] = (char)(0x80 | ((cp >> 6) & 0x3F));
      cpath[out++] = (char)(0x80 | (cp & 0x3F));
    }
  }
  cpath[out] = '\0';

  FILE *f = fopen(cpath, "rb");
  free(cpath);
  if (!f) {
    return moonbit_make_string(0, 0);
  }

  fseek(f, 0, SEEK_END);
  long fsize = ftell(f);
  fseek(f, 0, SEEK_SET);

  unsigned char *buf = (unsigned char *)malloc(fsize);
  if (!buf) {
    fclose(f);
    return moonbit_make_string(0, 0);
  }
  size_t nread = fread(buf, 1, fsize, f);
  fclose(f);

  moonbit_string_t result = utf8_to_moonbit_string(buf, (int)nread);
  free(buf);
  return result;
}
