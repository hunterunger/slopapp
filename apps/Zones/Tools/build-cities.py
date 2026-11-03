#!/usr/bin/env python3
"""Builds Zones' bundled city list from GeoNames.

    python3 -I apps/Zones/Tools/build-cities.py            # download + build
    python3 -I apps/Zones/Tools/build-cities.py --from DIR # reuse files already in DIR

Source: GeoNames (https://www.geonames.org), "cities15000" (every place with more than
15,000 people, plus seats of administrative divisions) and "admin1CodesASCII" (region
names). License: Creative Commons Attribution 4.0 (CC BY 4.0). Credit appears in the
app's About tab, apps/Zones/README.md and apps/Zones/THIRD_PARTY.md.

Output: Sources/ZonesCore/Resources/cities.tsv.deflate, raw DEFLATE (what
NSData.decompressed(using: .zlib) reads) of a UTF-8 TSV, one place per line:

    name <TAB> search keys <TAB> country code <TAB> region <TAB> population <TAB> time zone

Search keys are '|'-joined, already folded (lowercased, accents removed) the same way
ZonesCore folds a query (`SearchFolding.fold`): the name, its ASCII form and the alternate
names worth searching (capitalized Latin exonyms like "Munchen", codes like "NYC", and
Chinese/Japanese/Korean names). Lines are sorted by population, largest first. Lines
starting with '#' are comments.

Downloads go to a fresh temporary directory and are read as data only.
"""
import argparse
import os
import sys
import tempfile
import unicodedata
import urllib.request
import zipfile
import zlib

BASE = "https://download.geonames.org/export/dump/"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Sources", "ZonesCore", "Resources", "cities.tsv.deflate")
MAX_ALT_LENGTH = 40
KEPT_SCRIPTS = {"LATIN", "CJK", "HIRAGANA", "KATAKANA", "HANGUL"}


def fold(text):
    """Lowercase, then strip combining marks after compatibility decomposition.
    Must match SearchFolding.fold in ZonesCore."""
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in decomposed if unicodedata.category(c) != "Mn").strip()


def first_script(text):
    for char in text:
        if char.isalpha():
            return unicodedata.name(char, "").split(" ")[0]
    return ""


def download(directory):
    for name in ("cities15000.zip", "admin1CodesASCII.txt"):
        target = os.path.join(directory, name)
        print(f"downloading {BASE}{name}", file=sys.stderr)
        with urllib.request.urlopen(BASE + name, timeout=120) as response, open(target, "wb") as out:
            out.write(response.read())


def load_cities(directory):
    txt = os.path.join(directory, "cities15000.txt")
    if not os.path.exists(txt):
        with zipfile.ZipFile(os.path.join(directory, "cities15000.zip")) as archive:
            with archive.open("cities15000.txt") as source:
                return source.read().decode("utf-8").splitlines()
    with open(txt, encoding="utf-8") as source:
        return source.read().splitlines()


def load_regions(directory):
    regions = {}
    with open(os.path.join(directory, "admin1CodesASCII.txt"), encoding="utf-8") as source:
        for line in source:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                regions[parts[0]] = parts[1]
    return regions


def keep_alternate(name):
    if not name or len(name) > MAX_ALT_LENGTH or name.startswith("http"):
        return False
    script = first_script(name)
    if script not in KEPT_SCRIPTS:
        return False
    # GeoNames lists many lowercase machine transliterations ("aisakaladesa"); real
    # exonyms and codes start with a capital.
    return script != "LATIN" or name[0].isupper()


def clean(field):
    return field.replace("\t", " ").replace("|", " ").strip()


def build(directory):
    regions = load_regions(directory)
    places = []
    for line in load_cities(directory):
        cols = line.split("\t")
        if len(cols) < 19:
            continue
        name, ascii_name, alternates = cols[1], cols[2], cols[3]
        country, admin1, population, zone = cols[8], cols[10], cols[14], cols[17]
        if not zone or not name:
            continue
        keys = []
        for candidate in [name, ascii_name] + [a.strip() for a in alternates.split(",") if keep_alternate(a.strip())]:
            folded = clean(fold(candidate))
            if folded and folded not in keys:
                keys.append(folded)
        region = regions.get(f"{country}.{admin1}", "")
        if region == name:
            region = ""
        places.append((int(population or 0), clean(name), "|".join(keys), country, clean(region), zone))
    places.sort(key=lambda p: (-p[0], p[1]))
    header = "# GeoNames cities15000 (https://www.geonames.org), CC BY 4.0. Built by apps/Zones/Tools/build-cities.py\n"
    body = "\n".join(f"{n}\t{k}\t{c}\t{r}\t{p}\t{z}" for p, n, k, c, r, z in places)
    raw = (header + body + "\n").encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = compressor.compress(raw) + compressor.flush()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as out:
        out.write(data)
    print(f"{len(places)} places, {len(raw):,} bytes raw, {len(data):,} bytes compressed -> {os.path.relpath(OUT)}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from", dest="source", help="directory that already holds cities15000.zip (or .txt) and admin1CodesASCII.txt")
    args = parser.parse_args()
    if args.source:
        build(args.source)
    else:
        with tempfile.TemporaryDirectory(prefix="zones-geonames-") as directory:
            download(directory)
            build(directory)


if __name__ == "__main__":
    main()
