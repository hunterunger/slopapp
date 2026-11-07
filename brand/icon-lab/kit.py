#!/usr/bin/env python3
"""Shared tooling for round 2: per-app drawn layers -> .icon docs -> renders -> web images -> visual sheet.

A direction module defines   make(app, a) -> (background, groups, assets)   (same shape as lab.py)
and calls   kit.build("R2-Name", make)   at the bottom.

Outputs:  docs/R2-Name/<App>.icon, renders/R2-Name/*.png, web/R2-Name/*.webp, sheets/vis-R2-Name.webp
"""
import os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lab
from lab import (FLAVOURS, GRAPHITE, ICE, APPS, mix, c, solid, gradient, layer, group,
                 write_doc, svg_doc, lucide_parts, glyph_svg, solid_svg, fill_parts, ICTOOL)

LAB = lab.LAB
DOCK = ["Clips", "Snapper", "Switchboard", "Paper", "Tidy", "Commit", "Awake", "Dropper"]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def ictool(doc, out, rendition, pts, scale):
    subprocess.run([ICTOOL, doc, "--export-image", "--output-file", out, "--platform", "macOS",
                    "--rendition", rendition, "--width", str(pts), "--height", str(pts),
                    "--scale", str(scale)], capture_output=True)
    if not os.path.exists(out):
        print("ictool failed:", doc, rendition, file=sys.stderr)


def build(key, make, apps=DOCK):
    rdir, wdir = os.path.join(LAB, "renders", key), os.path.join(LAB, "web", key)
    os.makedirs(rdir, exist_ok=True)
    os.makedirs(wdir, exist_ok=True)
    jobs = []
    for app in apps:
        doc = os.path.join(LAB, "docs", key, f"{app}.icon")
        write_doc(doc, *make(app, APPS[app]))
        for r in lab.RENDITIONS:
            jobs.append((doc, os.path.join(rdir, f"{app}-{r}.png"), r, 256, 2))
        for pt in (16, 32):
            for r in ("Default", "Dark"):
                jobs.append((doc, os.path.join(wdir, f"{app}-{r}-{pt}pt.png"), r, pt, 2))
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda j: ictool(*j), jobs))
    # web copies
    for app in apps:
        for r in ("Default", "Dark"):
            subprocess.run(["magick", os.path.join(rdir, f"{app}-{r}.png"), "-resize", "192x192",
                            os.path.join(wdir, f"{app}-{r}.png")])
        for r in ("ClearLight", "ClearDark", "TintedLight", "TintedDark"):
            subprocess.run(["magick", os.path.join(rdir, f"{app}-{r}.png"), "-resize", "128x128",
                            os.path.join(wdir, f"{app}-{r}.png")])
    for f in os.listdir(wdir):
        if f.endswith(".png"):
            p = os.path.join(wdir, f)
            subprocess.run(["magick", p, "-quality", "88", "-define", "webp:alpha-quality=100",
                            p[:-4] + ".webp"])
    vis(key)
    print(f"{key}: built {len(apps)} apps -> sheets/vis-{key}.webp")


def vis(key):
    """Visual card (Dock on wallpaper, dark row, 16/32 pt, clear/tinted) as one 2x webp."""
    import sheet
    css = re.search(r"<style>(.*?)</style>", sheet.page([]), re.S).group(1)
    html = sheet.card(key, "", "", "", "")
    html = re.sub(r"<header>.*?</header>", "", html, flags=re.S)
    html = re.sub(r"<dl>.*?</dl>", "", html, flags=re.S).replace('class="card"', 'class="vis"')
    doc = (f"<!doctype html><html><head><meta charset='utf-8'><style>{css} body{{font-family:-apple-system,"
           f"system-ui;margin:0;width:696px;background:transparent}} .p32{{border-color:#8888}} "
           f".p32 .fh{{color:#888}}</style></head><body>{html}</body></html>")
    sd = os.path.join(LAB, "sheets")
    hp, png = os.path.join(sd, f"vis-{key}.html"), os.path.join(sd, f"vis-{key}.png")
    open(hp, "w").write(doc)
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--window-size=696,600",
                    "--force-device-scale-factor=2", "--default-background-color=00000000",
                    "--allow-file-access-from-files", f"--screenshot={png}", f"file://{hp}"],
                   capture_output=True)
    subprocess.run(["magick", png, "-trim", "+repage", "-quality", "90", "-define",
                    "webp:alpha-quality=100", png[:-4] + ".webp"])


def big_sheet(key, out=None):
    """A large review sheet (Default row + Dark row at 256 px) for checking detail."""
    rdir = os.path.join(LAB, "renders", key)
    files = [os.path.join(rdir, f"{a}-{r}.png") for r in ("Default", "Dark") for a in DOCK]
    out = out or os.path.join(LAB, "sheets", f"big-{key}.png")
    subprocess.run(["montage", *files, "-tile", "8x2", "-geometry", "200x200+8+8", "-background",
                    "#7a7a7a", "-font", "/System/Library/Fonts/Helvetica.ttc", out])
    return out
