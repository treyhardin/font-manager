#ifndef WOFF2KIT_H
#define WOFF2KIT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Encode an SFNT (OTF/TTF) into WOFF2.
/// On success returns 0 and sets *out / *out_len (caller frees *out with w2k_free).
/// Non-zero return = failure.
int w2k_sfnt_to_woff2(const uint8_t *data, size_t length, uint8_t **out, size_t *out_len);

/// Decode WOFF2 into an SFNT (OTF/TTF).
/// On success returns 0 and sets *out / *out_len (caller frees *out with w2k_free).
/// Non-zero return = failure.
int w2k_woff2_to_sfnt(const uint8_t *data, size_t length, uint8_t **out, size_t *out_len);

/// Free a buffer returned by the functions above.
void w2k_free(uint8_t *ptr);

#ifdef __cplusplus
}
#endif

#endif /* WOFF2KIT_H */
