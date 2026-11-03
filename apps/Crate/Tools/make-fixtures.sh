#!/usr/bin/env bash
# Makes test archives for walkthroughs and blind tests, all under /tmp/crate-test/fixtures.
# Uses only tools that ship with macOS (bsdtar = the system libarchive, ditto, zip, tar,
# gzip, split, python3 -I for hand-made hostile zips/tars) plus the RAR and encrypted 7z
# fixtures from the unit tests.
#
#   apps/Crate/Tools/make-fixtures.sh            # (re)creates /tmp/crate-test/fixtures
#
# Safe to run again: it deletes and recreates only /tmp/crate-test/fixtures.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT=/tmp/crate-test/fixtures
SRC=/tmp/crate-test/fixture-sources
rm -rf "$OUT" "$SRC"
mkdir -p "$OUT" "$SRC"

# --- Source files -------------------------------------------------------------
mkdir -p "$SRC/Project/docs" "$SRC/Project/images" "$SRC/Project/empty folder"
echo "Hello from Crate's test fixtures." > "$SRC/Project/README.md"
for i in 1 2 3 4 5; do printf 'Chapter %s\n%.0s' "$i" {1..200} > "$SRC/Project/docs/chapter $i.txt"; done
head -c 300000 /dev/urandom > "$SRC/Project/images/photo.jpg"
echo "junk" > "$SRC/Project/.DS_Store"
mkdir -p "$SRC/Ünïcødé 名前"
echo "Crème brûlée" > "$SRC/Ünïcødé 名前/Café menu.txt"
echo "📦" > "$SRC/Ünïcødé 名前/📦 box.txt"
echo "loose 1" > "$SRC/loose-1.txt"
echo "loose 2" > "$SRC/loose-2.txt"
head -c 3000000 /dev/urandom > "$SRC/big.bin"
mkdir -p "$SRC/many"
for i in $(seq 1 2000); do echo "file $i" > "$SRC/many/file-$i.txt"; done

cd "$SRC"
# --- Everyday archives --------------------------------------------------------
ditto -c -k --sequesterRsrc --keepParent Project "$OUT/Project (ditto).zip"
zip -qr "$OUT/loose files.zip" loose-1.txt loose-2.txt Project/README.md
tar -czf "$OUT/Project.tar.gz" Project
bsdtar -cJf "$OUT/Project.tar.xz" Project
bsdtar -cjf "$OUT/Project.tar.bz2" Project
bsdtar -c --format 7zip -f "$OUT/Project.7z" Project
bsdtar -c --format zip --options zip:hdrcharset=UTF-8 -f "$OUT/Unicode names.zip" "Ünïcødé 名前"
cp Project/README.md readme-copy.md && gzip -c readme-copy.md > "$OUT/single file.md.gz"
zip -qr "$OUT/2000 files.zip" many
zip -q "$OUT/empty.zip" -r -i 'nothing' . 2>/dev/null || python3 -I -c "import zipfile; zipfile.ZipFile('$OUT/empty.zip','w').close()"

# --- Passwords (password: secret) ------------------------------------------------
bsdtar -c --format zip --options zip:encryption=aes256 --passphrase secret -f "$OUT/password AES (secret).zip" Project
zip -q -r -P secret "$OUT/password ZipCrypto (secret).zip" Project
cp "$HERE/../Tests/CrateCoreTests/Fixtures/encrypted_data.7z" "$OUT/password (secret).7z"
cp "$HERE/../Tests/CrateCoreTests/Fixtures/encrypted_header.7z" "$OUT/password hidden names (secret).7z"
cp "$HERE/../Tests/CrateCoreTests/Fixtures/rar_encryption_header.rar" "$OUT/password.rar"

# --- RAR (from libarchive's test suite) ----------------------------------------------
cp "$HERE/../Tests/CrateCoreTests/Fixtures/rar5_solid.rar" "$OUT/solid.rar"
cp "$HERE/../Tests/CrateCoreTests/Fixtures/rar.rar" "$OUT/old.rar"

# --- Split sets ------------------------------------------------------------------
mkdir -p "$OUT/split"
zip -q "$SRC/bigzip.zip" big.bin && split -b 1000000 -a 3 "$SRC/bigzip.zip" "$OUT/split/big.zip."
# split names parts .aaa/.aab; rename to .001/.002…
n=1; for f in "$OUT/split/big.zip."???; do mv "$f" "$OUT/split/big.zip.$(printf %03d $n)"; n=$((n+1)); done
bsdtar -c --format 7zip -f "$SRC/big.7z" big.bin && split -b 1000000 -a 3 "$SRC/big.7z" "$OUT/split/big.7z."
n=1; for f in "$OUT/split/big.7z."[a-z][a-z][a-z]; do mv "$f" "$OUT/split/big.7z.$(printf %03d $n)"; n=$((n+1)); done
zip -q -s 1m "$OUT/split/spanned.zip" big.bin
for i in 1 2 3 4 5 6 7 8; do cp "$HERE/../Tests/CrateCoreTests/Fixtures/rar5_multiarchive.part0$i.rar" "$OUT/split/movie.part$i.rar"; done
mkdir -p "$OUT/split-missing-part"
cp "$OUT/split/big.7z.001" "$OUT/split/big.7z.003" "$OUT/split-missing-part/"

# --- Hostile and broken archives ----------------------------------------------------
mkdir -p "$OUT/hostile"
python3 -I - "$OUT/hostile" <<'PY'
import io, os, stat, sys, tarfile, time, zipfile
out = sys.argv[1]
# Path traversal and absolute paths.
with zipfile.ZipFile(os.path.join(out, "traversal.zip"), "w") as z:
    z.writestr("../../escaped-from-crate.txt", "If you can read this outside the extract folder, the extractor is unsafe.\n")
    z.writestr("/tmp/crate-test/absolute-escape.txt", "absolute path\n")
    z.writestr("safe/inside.txt", "this one is fine\n")
# Symlink attacks (tar): a link pointing outside, then a file written through it; an
# absolute link; a link then a same-named file.
def add(t, name, data=None, link=None, kind=tarfile.REGTYPE):
    info = tarfile.TarInfo(name); info.mtime = time.time()
    if link is not None:
        info.type = kind; info.linkname = link; t.addfile(info)
    elif data is None:
        info.type = tarfile.DIRTYPE; info.mode = 0o755; t.addfile(info)
    else:
        info.size = len(data); t.addfile(info, io.BytesIO(data))
with tarfile.open(os.path.join(out, "symlink escape.tar"), "w") as t:
    add(t, "escape", link="../../../..", kind=tarfile.SYMTYPE)
    add(t, "escape/tmp/crate-test/pwned.txt", b"written through a symlink\n")
    add(t, "etc-link", link="/etc", kind=tarfile.SYMTYPE)
    add(t, "etc-link/crate-pwned", b"bad\n")
    add(t, "swap", link="../../../tmp/crate-test/fixtures/hostile/TARGET.txt", kind=tarfile.SYMTYPE)
    add(t, "swap", b"overwrote the target through a link\n")
    add(t, "docs/", None)
    add(t, "docs/real.txt", b"fine\n")
    add(t, "good-link", link="docs/real.txt", kind=tarfile.SYMTYPE)
    add(t, "hardlink-escape", link="../../../etc/hosts", kind=tarfile.LNKTYPE)
with open(os.path.join(out, "TARGET.txt"), "w") as f:
    f.write("original target text\n")
# Setuid bit and a device-like entry.
with tarfile.open(os.path.join(out, "setuid.tar"), "w") as t:
    info = tarfile.TarInfo("tool"); info.mode = 0o4755; data = b"#!/bin/sh\necho hi\n"; info.size = len(data)
    t.addfile(info, io.BytesIO(data))
    info = tarfile.TarInfo("fifo"); info.type = tarfile.FIFOTYPE; t.addfile(info)
# Case clash and duplicates.
with zipfile.ZipFile(os.path.join(out, "case clash.zip"), "w") as z:
    z.writestr("README", "upper\n"); z.writestr("readme", "lower\n")
    z.writestr("a.txt", "first\n"); z.writestr("a.txt", "second\n")
# Zip bomb: 2 GB of zeros in a ~2 MB zip.
with zipfile.ZipFile(os.path.join(out, "zip bomb.zip"), "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    with z.open("zeros.bin", "w", force_zip64=True) as f:
        chunk = bytes(1 << 20)
        for _ in range(2048):
            f.write(chunk)
PY
# Corrupt and truncated.
cp "$OUT/Project.tar.gz" "$OUT/hostile/truncated.tar.gz"
python3 -I - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
p = os.path.join(out, "hostile/truncated.tar.gz")
data = open(p, "rb").read(); open(p, "wb").write(data[: len(data) // 2])
src = open(os.path.join(out, "Project.7z"), "rb").read()
bad = bytearray(src); 
for i in range(40, min(len(bad), 400)): bad[i] ^= 0xFF
open(os.path.join(out, "hostile/corrupt.7z"), "wb").write(bytes(bad))
open(os.path.join(out, "hostile/not really a zip.zip"), "w").write("This is a text file with a .zip name.\n" * 20)
PY

# A quarantined download (as if from a browser).
cp "$OUT/loose files.zip" "$OUT/downloaded (quarantined).zip"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$OUT/downloaded (quarantined).zip"

# Files to compress.
mkdir -p "$OUT/to compress"
cp -R "$SRC/Project" "$SRC/Ünïcødé 名前" "$SRC/loose-1.txt" "$SRC/big.bin" "$OUT/to compress/"

echo "Fixtures in $OUT:"
(cd "$OUT" && find . -type f | sort | sed 's/^\.\//  /')
