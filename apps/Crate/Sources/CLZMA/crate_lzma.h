// crate_lzma.h: the subset of liblzma's public API that Crate uses (raw LZMA/LZMA2/BCJ
// decoding of 7z headers and of the first bytes of encrypted 7z data, to check passwords).
//
// macOS ships liblzma (/usr/lib/liblzma.5.dylib, in the dyld shared cache) and the SDK
// ships its link stub (usr/lib/liblzma.tbd), but not lzma.h. These declarations follow
// liblzma 5.x's public headers (public domain / 0BSD, https://tukaani.org/xz/). The
// stream struct layout has been stable since liblzma 5.0; enums are passed as int.
#ifndef CRATE_LZMA_H
#define CRATE_LZMA_H

#include <stddef.h>
#include <stdint.h>

typedef uint64_t lzma_vli;

#define LZMA_OK 0
#define LZMA_STREAM_END 1
#define LZMA_BUF_ERROR 10

#define LZMA_RUN 0
#define LZMA_FINISH 3

#define LZMA_VLI_UNKNOWN UINT64_MAX
#define LZMA_FILTER_LZMA1 0x4000000000000001ULL
#define LZMA_FILTER_LZMA2 0x21ULL
#define LZMA_FILTER_DELTA 0x03ULL
#define LZMA_FILTER_X86 0x04ULL
#define LZMA_FILTER_POWERPC 0x05ULL
#define LZMA_FILTER_IA64 0x06ULL
#define LZMA_FILTER_ARM 0x07ULL
#define LZMA_FILTER_ARMTHUMB 0x08ULL
#define LZMA_FILTER_SPARC 0x09ULL

typedef struct {
    lzma_vli id;
    void *options;
} lzma_filter;

typedef struct {
    const uint8_t *next_in;
    size_t avail_in;
    uint64_t total_in;
    uint8_t *next_out;
    size_t avail_out;
    uint64_t total_out;
    const void *allocator;
    void *internal;
    void *reserved_ptr1;
    void *reserved_ptr2;
    void *reserved_ptr3;
    void *reserved_ptr4;
    uint64_t reserved_int1;
    uint64_t reserved_int2;
    size_t reserved_int3;
    size_t reserved_int4;
    int reserved_enum1;
    int reserved_enum2;
} lzma_stream;

uint32_t lzma_version_number(void);
int lzma_raw_decoder(lzma_stream *strm, const lzma_filter *filters);
int lzma_code(lzma_stream *strm, int action);
void lzma_end(lzma_stream *strm);
int lzma_properties_decode(lzma_filter *filter, const void *allocator, const uint8_t *props, size_t props_size);

#endif
