// crate_archive.h: the subset of libarchive's public API that Crate uses.
//
// macOS ships libarchive (/usr/lib/libarchive.2.dylib, in the dyld shared cache) and the
// SDK ships its link stub (usr/lib/libarchive.tbd), but not archive.h / archive_entry.h.
// These declarations are copied by signature from libarchive 3.x's public headers
// (BSD-2-Clause, https://github.com/libarchive/libarchive). Every type that crosses the
// boundary is an opaque pointer or a fixed-size integer, so this is ABI-safe.
//
// Rules for editing: only add functions that exist in libarchive 3.3 (macOS 14's copy is
// newer), keep the exact C signatures, and keep it small. Check
// `archive_version_number()` at runtime before relying on anything newer.
#ifndef CRATE_ARCHIVE_H
#define CRATE_ARCHIVE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

struct archive;
struct archive_entry;

// Return codes.
#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

// archive_format() codes (base format in the top bits).
#define ARCHIVE_FORMAT_BASE_MASK 0xff0000
#define ARCHIVE_FORMAT_CPIO 0x10000
#define ARCHIVE_FORMAT_TAR 0x30000
#define ARCHIVE_FORMAT_ISO9660 0x40000
#define ARCHIVE_FORMAT_ZIP 0x50000
#define ARCHIVE_FORMAT_AR 0x70000
#define ARCHIVE_FORMAT_RAW 0x90000
#define ARCHIVE_FORMAT_XAR 0xA0000
#define ARCHIVE_FORMAT_LHA 0xB0000
#define ARCHIVE_FORMAT_CAB 0xC0000
#define ARCHIVE_FORMAT_RAR 0xD0000
#define ARCHIVE_FORMAT_7ZIP 0xE0000
#define ARCHIVE_FORMAT_RAR_V5 0x100000

// archive_filter_code() values.
#define ARCHIVE_FILTER_NONE 0
#define ARCHIVE_FILTER_GZIP 1
#define ARCHIVE_FILTER_BZIP2 2
#define ARCHIVE_FILTER_COMPRESS 3
#define ARCHIVE_FILTER_LZMA 5
#define ARCHIVE_FILTER_XZ 6

// archive_read_has_encrypted_entries() answers besides 0/1.
#define ARCHIVE_READ_FORMAT_ENCRYPTION_UNSUPPORTED (-2)
#define ARCHIVE_READ_FORMAT_ENCRYPTION_DONT_KNOW (-1)

// archive_write_disk_set_options() flags.
#define ARCHIVE_EXTRACT_TIME (0x0004)
#define ARCHIVE_EXTRACT_NO_OVERWRITE (0x0008)
#define ARCHIVE_EXTRACT_SECURE_SYMLINKS (0x0100)
#define ARCHIVE_EXTRACT_SECURE_NODOTDOT (0x0200)
#define ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS (0x10000)

// File types (archive_entry_filetype()).
#define AE_IFMT 0170000
#define AE_IFREG 0100000
#define AE_IFLNK 0120000
#define AE_IFDIR 0040000

int archive_version_number(void);
const char *archive_version_details(void);

// Shared.
int archive_errno(struct archive *);
const char *archive_error_string(struct archive *);
int archive_format(struct archive *);
const char *archive_format_name(struct archive *);
int archive_filter_count(struct archive *);
int archive_filter_code(struct archive *, int);
int64_t archive_filter_bytes(struct archive *, int);

// Reading.
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_support_format_raw(struct archive *);
int archive_read_set_options(struct archive *, const char *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_open_filenames(struct archive *, const char **, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_block(struct archive *, const void **, size_t *, int64_t *);
int archive_read_data_skip(struct archive *);
int archive_read_has_encrypted_entries(struct archive *);
int archive_read_close(struct archive *);
int archive_read_free(struct archive *);

// Entries.
struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
struct archive_entry *archive_entry_clear(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_symlink_utf8(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
const char *archive_entry_hardlink_utf8(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
int archive_entry_mtime_is_set(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
int archive_entry_is_data_encrypted(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
void archive_entry_set_symlink_utf8(struct archive_entry *, const char *);
void archive_entry_set_hardlink_utf8(struct archive_entry *, const char *);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_unset_size(struct archive_entry *);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, mode_t);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);

// Writing archives.
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_set_options(struct archive *, const char *);
int archive_write_set_passphrase(struct archive *, const char *);
int archive_write_open_filename(struct archive *, const char *);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

// Writing to disk (extraction).
struct archive *archive_write_disk_new(void);
int archive_write_disk_set_options(struct archive *, int);
ssize_t archive_write_data_block(struct archive *, const void *, size_t, int64_t);

#endif
