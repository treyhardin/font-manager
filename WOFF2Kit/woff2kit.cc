#include "woff2kit.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include <woff2/encode.h>
#include <woff2/decode.h>
#include <woff2/output.h>

extern "C" {

int w2k_sfnt_to_woff2(const uint8_t *data, size_t length, uint8_t **out, size_t *out_len) {
    if (!data || !out || !out_len) return 1;

    size_t maxSize = woff2::MaxWOFF2CompressedSize(data, length);
    uint8_t *buffer = static_cast<uint8_t *>(std::malloc(maxSize > 0 ? maxSize : 1));
    if (!buffer) return 1;

    size_t resultLength = maxSize;
    if (!woff2::ConvertTTFToWOFF2(data, length, buffer, &resultLength)) {
        std::free(buffer);
        return 2;
    }

    *out = buffer;
    *out_len = resultLength;
    return 0;
}

int w2k_woff2_to_sfnt(const uint8_t *data, size_t length, uint8_t **out, size_t *out_len) {
    if (!data || !out || !out_len) return 1;

    std::string output;
    woff2::WOFF2StringOut sink(&output);
    if (!woff2::ConvertWOFF2ToTTF(data, length, &sink)) {
        return 2;
    }

    size_t size = output.size();
    uint8_t *buffer = static_cast<uint8_t *>(std::malloc(size > 0 ? size : 1));
    if (!buffer) return 1;
    if (size > 0) std::memcpy(buffer, output.data(), size);

    *out = buffer;
    *out_len = size;
    return 0;
}

void w2k_free(uint8_t *ptr) {
    std::free(ptr);
}

}  // extern "C"
