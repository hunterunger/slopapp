#!/usr/bin/env python3
"""Slopapp app icons: the Nordic herbarium style. The spec is brand/ICONS.md; this file enforces it.

    python3 scripts/icons/herbarium.py build  [App ...] [--out DIR]   # write apps/<App>/AppIcon.icon (unchanged files are left alone)
    python3 scripts/icons/herbarium.py check  [App ...]               # enforce the rules (exit 1 on failure)
    python3 scripts/icons/herbarium.py render [App ...]               # build/icons/: renders, review sheet, construction SVGs
    python3 scripts/icons/herbarium.py new    <App>                   # start apps/<App>/Icon.py from _template.py
    python3 scripts/icons/herbarium.py tiles                          # which tile colours are taken, which are free
    python3 scripts/icons/herbarium.py plates <word ...>              # search the Köhler plate index
    python3 scripts/icons/herbarium.py fetch  <App> "<Commons file>"  # download a plate, licence-checked

Each app is one spec file, apps/<App>/Icon.py (drawing, colours, plate). Everything that makes the
style (grid, weights, palette rules, materials, print, clear zones) lives here, so a new app can only
differ in what the spec is allowed to say.

Plates live in brand/plates/: the processed one-colour prints (prints/<App>.png, committed), the
Köhler index, sources.json and SOURCES.md. The raw downloads (raw/) are not committed; they're only
needed to re-crop a print (and that step needs ImageMagick). Building and checking need neither.
"""
import sys
sys.dont_write_bytecode = True   # importing apps/<App>/Icon.py must not leave __pycache__ in the app

import base64, colorsys, importlib.util, json, math, os, re, shutil, subprocess, time
import urllib.error, urllib.parse, urllib.request
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
APPS = os.path.join(ROOT, "apps")                      # specs: apps/<App>/Icon.py
TEMPLATE = os.path.join(HERE, "_template.py")
PLATE_DIR = os.path.join(ROOT, "brand", "plates")
PLATES = os.path.join(PLATE_DIR, "raw")                # source plates (JPEG, as downloaded; not committed)
PRINTS = os.path.join(PLATE_DIR, "prints")             # processed one-colour prints (committed)
WORK = os.path.join(PLATE_DIR, ".work")                # intermediate files while processing (not committed)
SOURCES = os.path.join(PLATE_DIR, "sources.json")
SOURCES_MD = os.path.join(PLATE_DIR, "SOURCES.md")
INDEX = os.path.join(PLATE_DIR, "commons-koehler-meta.json")
RENDERS = os.path.join(ROOT, "build", "icons")


def ictool_path():
    try:
        dev = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    except OSError:
        dev = ""
    for base in (os.path.join(dev, ".."), "/Applications/Xcode.app/Contents"):
        tool = os.path.join(base, "Applications", "Icon Composer.app", "Contents", "Executables", "ictool")
        if os.path.exists(tool):
            return os.path.abspath(tool)
    return None


# ------------------------------------------------------------------ construction tokens
U, M = 32, 64              # every anchor is a multiple of U; layout snaps to M
W1, W2, H = 128, 64, 32    # the only weights: bodies/tracks, lines/rims, cuts/slits
G = 64                     # gap between neighbouring parts
TILE_R = 256               # the macOS tile corner; near the edge, r = TILE_R - inset
BEND_R = 256               # every route bend
CLEAR = 32                 # unprinted margin around anything sitting on a print
BLEED = 64                 # shapes that leave the tile go to -64 / 1088
MAX_DEPTH = 3              # back (the tile thing), middle, front

# ------------------------------------------------------------------ palette
BIRCH, CHAR, WALNUT, NIGHT = "#F5F0E8", "#2F2D2A", "#5B4636", "#24231F"
DARK_SURFACE, DARK_BASE, DARK_INK = "#3B3833", "#E8E1D5", "#171614"
ROLES = ("surface", "base", "muted", "main", "main2", "main3", "accent", "ink")

# Tile colours. Each app owns one; new apps take an unused one (`herbarium.py tiles` lists them), or
# add a muted, natural colour here. Order matters: `new` gives a new app the first free one.
TILES = {
    "ochre": "#D2A04C", "clay": "#C4704F", "fjord": "#5D7E9A", "sage": "#8EA58B", "pine": "#3F5E4E",
    "heather": "#8C7EA0", "rosewood": "#A9665C", "blush": "#D9B8B0",
    "lingonberry": "#A8443A", "lichen": "#A9AE7E", "slate": "#59626B", "sand": "#CDB892",
    "moss": "#6B7A45", "dusk": "#46597A", "rust": "#9A5A36", "juniper": "#2F4F57", "rye": "#B8955F",
    "mist": "#9FB3C2", "bark": "#8A847A", "cloudberry": "#DE9F57",
    "bilberry": "#5B5A84",
    "tarn": "#4F7D78",
}
ACCENTS = {"lingonberry": "#B9473B", "ochre": "#E0B054", "clay": "#C4704F", "spruce": "#4F7A72"}


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    a, b = hx(a), hx(b)
    return "#" + "".join(f"{round((x + (y - x) * t) * 255):02X}" for x, y in zip(a, b))


def srgb(h):
    r, g, b = hx(h)
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def luminance(h):
    def lin(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in hx(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# ------------------------------------------------------------------ primitives (white artwork)

def on_grid(*vals):
    for v in vals:
        if abs(v / U - round(v / U)) > 1e-6:
            raise ValueError(f"{v} is off the {U}-unit grid")
    return vals


def svg_doc(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>')


def rect(x, y, w, h, r=0):
    on_grid(x, y, w, h)
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#FFF"/>'


def pill(x, y, w, h):
    return rect(x, y, w, h, min(w, h) / 2)


def disc(cx, cy, r):
    on_grid(cx, cy, r)
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF"/>'


def ring(cx, cy, r, w):
    """Ring of outer radius r and width w; the hole shows what is below."""
    on_grid(cx, cy, r, w)
    r2 = r - w
    return (f'<path fill="#FFF" fill-rule="evenodd" d="M{cx - r},{cy}a{r},{r} 0 1,0 {2 * r},0'
            f'a{r},{r} 0 1,0 {-2 * r},0zM{cx - r2},{cy}a{r2},{r2} 0 1,0 {2 * r2},0'
            f'a{r2},{r2} 0 1,0 {-2 * r2},0z"/>')


def stroke(d, w):
    if w not in (W1, W2, H):
        raise ValueError(f"stroke width {w} is not one of {W1}/{W2}/{H}")
    return (f'<path d="{d}" fill="none" stroke="#FFF" stroke-width="{w}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>')


def rpoly(pts, r=32):
    """Convex polygon with every corner rounded to r (offset inwards by r, then stroked 2r)."""
    for p in pts:
        on_grid(*p)
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    s = 1 if area > 0 else -1
    lines = []
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        lines.append(((x1 - dy / L * s * r, y1 + dx / L * s * r), (dx, dy)))
    inner = []
    for i in range(n):
        (p, d1), (q, d2) = lines[i - 1], lines[i]
        t = ((q[0] - p[0]) * d2[1] - (q[1] - p[1]) * d2[0]) / (d1[0] * d2[1] - d1[1] * d2[0])
        inner.append((p[0] + d1[0] * t, p[1] + d1[1] * t))
    d = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in inner) + " Z"
    return f'<path d="{d}" fill="#FFF" stroke="#FFF" stroke-width="{2 * r}" stroke-linejoin="round"/>'


def rot(body, x, y, deg):
    """Draw `body` in its own frame (origin at (x, y)), turned by deg. Only 0/45/90-degree turns."""
    on_grid(x, y)
    if deg % 45:
        raise ValueError(f"rotation {deg} is not a multiple of 45")
    return f'<g transform="translate({x} {y}) rotate({deg})">{body}</g>'


def cut(body, holes, mid):
    """`body` with `holes` (white artwork) removed."""
    black = holes.replace('fill="#FFF"', 'fill="#000"').replace('stroke="#FFF"', 'stroke="#000"')
    return (f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424">'
            f'<rect x="-200" y="-200" width="1424" height="1424" fill="#FFF"/>{black}</mask>'
            f'<g mask="url(#{mid})">{body}</g>')


def bend_route(x0, y0, y1, R=BEND_R):
    """Transit-map route from (x0, y0) heading east to y = y1: 45-degree arc, diagonal, arc, straight."""
    on_grid(x0, y0, y1)
    s = -1 if y1 < y0 else 1
    k = math.sqrt(0.5)
    p1 = (x0 + k * R, y0 + s * (R - k * R))
    dy = abs(y1 - y0) - 2 * (R - k * R)
    q = (p1[0] + dy, p1[1] + s * dy)
    e = (q[0] + k * R, y1)
    sw1, sw2 = (0, 1) if s < 0 else (1, 0)
    return (f"M{x0},{y0} A{R},{R} 0 0 {sw1} {p1[0]:.2f},{p1[1]:.2f} L{q[0]:.2f},{q[1]:.2f} "
            f"A{R},{R} 0 0 {sw2} {e[0]:.2f},{e[1]:.2f} L1088,{y1}")


def halo(svg, pad=CLEAR):
    """Black knock-out of white artwork, grown by `pad` on every side (for print masks)."""
    def grow(m):
        tag = m.group(0)
        sw = re.search(r'stroke-width="([\d.]+)"', tag)
        if sw:
            tag = tag.replace(sw.group(0), f'stroke-width="{float(sw.group(1)) + 2 * pad}"')
            tag = tag.replace('stroke="#FFF"', 'stroke="#000"')
        else:
            tag = tag.replace("/>", f' stroke="#000" stroke-width="{2 * pad}" stroke-linejoin="round"/>')
        return tag.replace('fill="#FFF"', 'fill="#000"')
    return re.sub(r"<(?:rect|circle|path)\b[^>]*/>", grow, svg)


# ------------------------------------------------------------------ spec

@dataclass
class Part:
    name: str
    svg: str
    role: str
    depth: int            # 0 = front
    on: str = None        # role of what it sits on, for the contrast check ("tile" allowed)


@dataclass
class Print:
    plate: str                          # plate file in brand/plates/raw (App.jpg)
    crop: tuple                         # (x, y, size): square in plate pixels
    on: str = "ground"                  # "ground" or the name of the part it fills
    erase: list = field(default_factory=list)   # [(x, y, w, h)] labels/figures to paint out
    clear: list = field(default_factory=list)   # parts sitting on the print (get a CLEAR zone)
    mask: str = None                    # custom mask (white artwork) when the part has its own mask
    flip: bool = False
    plant: tuple = None                 # (botanical name, common name): credits and the website


@dataclass
class Spec:
    name: str
    tile: str                           # a TILES value
    main: str
    main2: str
    main3: str
    accent: str
    muted: str
    parts: object                       # () -> [Part]
    print: Print
    light: dict = field(default_factory=dict)   # per-role overrides
    dark: dict = field(default_factory=dict)


def spec_path(app):
    return os.path.join(APPS, app, "Icon.py")


def load(app):
    path = spec_path(app)
    if not os.path.exists(path):
        sys.exit(f"{app}: no {os.path.relpath(path, ROOT)} (herbarium.py new {app})")
    if HERE not in sys.path:      # specs do `from herbarium import *`
        sys.path.insert(0, HERE)
    mod_spec = importlib.util.spec_from_file_location(f"icon_{app}", path)
    mod = importlib.util.module_from_spec(mod_spec)
    sys.modules[mod_spec.name] = mod
    mod_spec.loader.exec_module(mod)
    return mod.SPEC


def all_apps():
    return sorted(d for d in os.listdir(APPS) if os.path.isfile(spec_path(d)))


def colours(spec):
    light = dict(surface=BIRCH, base=BIRCH, muted=spec.muted, main=spec.main, main2=spec.main2,
                 main3=spec.main3, accent=spec.accent, ink=CHAR, tile=spec.tile)
    dark = dict(surface=DARK_SURFACE, base=DARK_BASE, muted=mix(spec.muted, NIGHT, 0.55),
                main=mix(spec.main, "#FFFFFF", 0.08), main2=mix(spec.main2, NIGHT, 0.45),
                main3=mix(spec.main3, NIGHT, 0.10), accent=mix(spec.accent, "#FFFFFF", 0.05),
                ink=DARK_INK, tile=mix(spec.tile, NIGHT, 0.66))
    light.update(spec.light)
    dark.update(spec.dark)
    return light, dark


# ------------------------------------------------------------------ prints

def print_key(spec):
    p = spec.print
    return json.dumps([p.plate, p.crop, p.erase, p.flip])


def print_state(spec):
    """"current" (the committed print matches the spec), "stale" (crop/erase changed; the plate is
    downloaded, so it can be re-processed), or a reason the print can't be made."""
    out = os.path.join(PRINTS, f"{spec.name}.png")
    stamp = out + ".key"
    if os.path.exists(out) and os.path.exists(stamp) and open(stamp).read() == print_key(spec):
        return "current"
    if os.path.exists(os.path.join(PLATES, spec.print.plate)):
        return "stale"
    if os.path.exists(out):
        return (f"prints/{spec.name}.png doesn't match the spec's crop/erase and the plate "
                f"(raw/{spec.print.plate}) isn't downloaded to re-process it (herbarium.py fetch)")
    return f"plate {spec.print.plate} is missing (herbarium.py fetch)"


def print_png(spec):
    """One-colour print of the plate: white, alpha = ink density, 1024 square. Committed to
    brand/plates/prints and re-processed (ImageMagick) only when the spec's crop/erase change."""
    p = spec.print
    key = print_key(spec)
    out = os.path.join(PRINTS, f"{spec.name}.png")
    stamp = out + ".key"
    state = print_state(spec)
    if state == "current":
        return out
    if state != "stale":
        raise ValueError(state)
    os.makedirs(PRINTS, exist_ok=True)
    os.makedirs(WORK, exist_ok=True)
    src = os.path.join(PLATES, p.plate)
    if p.erase:  # separate step: IM blanks the image if draw and resize share a command
        clean = os.path.join(WORK, f"{spec.name}-clean.png")
        cmd = ["magick", src, "-fill", "#FFFFFF"]
        for ex, ey, ew, eh in p.erase:
            cmd += ["-draw", f"rectangle {ex},{ey} {ex + ew},{ey + eh}"]
        subprocess.run(cmd + [clean], check=True)
        src = clean
    x, y, s = p.crop
    # white point just under this plate's paper tone, so bare paper is fully transparent
    paper = float(subprocess.run(["magick", src, "-alpha", "off", "-colorspace", "gray", "-format",
                                  "%[fx:median]", "info:"], capture_output=True, text=True).stdout)
    wp = max(60, min(92, paper * 100 - 6))
    alpha = os.path.join(WORK, f"{spec.name}-alpha.png")
    cmd = ["magick", src, "-alpha", "off", "-crop", f"{s}x{s}+{x}+{y}", "+repage"]
    if p.flip:
        cmd += ["-flop"]
    cmd += ["-colorspace", "gray", "-level", f"18%,{wp:.0f}%", "-negate", "-resize", "1024x1024!", alpha]
    subprocess.run(cmd, check=True)
    subprocess.run(["magick", "-size", "1024x1024", "xc:white", alpha, "-alpha", "off", "-compose",
                    "CopyOpacity", "-composite", "-define", "png:color-type=4", out], check=True)
    open(stamp, "w").write(key)
    return out


def print_svg(spec, mask):
    b64 = base64.b64encode(open(print_png(spec), "rb").read()).decode()
    img = f'<image x="0" y="0" width="1024" height="1024" xlink:href="data:image/png;base64,{b64}"/>'
    if mask:
        img = (f'<mask id="print" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424">'
               f'{mask}</mask><g mask="url(#print)">{img}</g>')
    return img


# ------------------------------------------------------------------ assemble

def fill(lc, dc):
    return {"fill-specializations": [{"value": {"solid": srgb(lc)}},
                                     {"appearance": "dark", "value": {"solid": srgb(dc)}}]}


def assemble(spec):
    """-> icon.json dict and {asset name: svg}."""
    light, dark = colours(spec)
    parts = [(p.name, p.svg, p.role, p.depth, False) for p in spec.parts()]
    pr = spec.print
    if pr.on == "ground":
        parts.append(("print", print_svg(spec, None), "tile", max(p[3] for p in parts), True))
    else:
        i = next(i for i, p in enumerate(parts) if p[0] == pr.on)
        mask = (pr.mask or parts[i][1]) + "".join(halo(s) for n, s, *_ in parts if n in pr.clear)
        parts.insert(i, ("print", print_svg(spec, mask), parts[i][2], parts[i][3], True))
    depths = sorted({p[3] for p in parts})
    groups, assets = [], {}
    for dpt in depths:
        layers = []
        for name, svg, role, d, is_print in parts:
            if d != dpt:
                continue
            assets[name] = svg_doc(svg)
            if is_print and role in ("surface", "base"):     # birch: printed in the app's tile colour
                lc, dc = mix(light[role], light["tile"], 0.5), mix(dark[role], "#FFFFFF", 0.14)
            elif is_print:                                    # coloured: tone-on-tone
                lc, dc = mix(light[role], CHAR, 0.30), mix(dark[role], "#FFFFFF", 0.16)
            else:
                lc, dc = light[role], dark[role]
            layers.append({"name": name, "image-name": f"{name}.svg", "glass": False,
                           "position": {"scale": 1, "translation-in-points": [0, 0]}, **fill(lc, dc)})
        groups.append({"layers": layers,
                       "shadow": {"kind": "neutral", "opacity": 0.18 if dpt < depths[-1] else 0.1},
                       "translucency": {"enabled": False, "value": 0.5}, "specular": False})
    t = spec.tile
    doc = {"fill-specializations": [
        {"value": {"linear-gradient": [srgb(mix(t, "#FFFFFF", 0.04)), srgb(mix(t, CHAR, 0.06))]}},
        {"appearance": "dark", "value": {"linear-gradient": [srgb(mix(t, NIGHT, 0.62)), srgb(mix(t, NIGHT, 0.72))]}}],
        "groups": groups, "supported-platforms": {"squares": "shared"}}
    return doc, assets


def icon_files(spec):
    """{relative path: text} of the .icon document."""
    doc, assets = assemble(spec)
    files = {os.path.join("Assets", f"{name}.svg"): svg for name, svg in assets.items()}
    files["icon.json"] = json.dumps(doc, indent=2)
    return files


def read_tree(path):
    files = {}
    for d, _, names in os.walk(path):
        for n in names:
            if n == ".DS_Store":
                continue
            f = os.path.join(d, n)
            try:
                files[os.path.relpath(f, path)] = open(f, encoding="utf-8").read()
            except UnicodeDecodeError:
                files[os.path.relpath(f, path)] = None
    return files


def write_icon(spec, path):
    """Writes the .icon document; returns False (and touches nothing) when it's already up to date."""
    files = icon_files(spec)
    if os.path.isdir(path) and read_tree(path) == files:
        return False
    tmp = path.rstrip("/") + ".tmp"
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(os.path.join(tmp, "Assets"))
    for rel, text in files.items():
        with open(os.path.join(tmp, rel), "w", encoding="utf-8") as f:
            f.write(text)
    if os.path.exists(path):
        shutil.rmtree(path)
    os.rename(tmp, path)
    return True


# ------------------------------------------------------------------ check

def check(spec, others=()):
    """Returns (errors, warnings). Errors fail the build."""
    errs, warn = [], []
    try:
        parts = spec.parts()
    except ValueError as e:
        return [f"drawing: {e}"], warn
    names = [p.name for p in parts]
    if len(set(names)) != len(names):
        errs.append("part names must be unique")
    for p in parts:
        if p.role not in ROLES:
            errs.append(f"{p.name}: unknown role {p.role!r}")
        if not 0 <= p.depth < MAX_DEPTH:
            errs.append(f"{p.name}: depth {p.depth} outside 0..{MAX_DEPTH - 1}")
        for w in re.findall(r'stroke-width="([\d.]+)"', p.svg):  # includes rpoly corners (2r)
            if float(w) not in (W1, W2, H):
                errs.append(f"{p.name}: stroke width {w} is not {W1}/{W2}/{H}")
    if not any(p.role == "accent" for p in parts):
        warn.append("no part uses the accent; make sure one part clearly 'acts'")
    if spec.tile.upper() not in (v.upper() for v in TILES.values()):
        errs.append(f"tile {spec.tile} is not in the TILES palette")
    for other in others:
        if other.name != spec.name and other.tile.upper() == spec.tile.upper():
            errs.append(f"tile {spec.tile} is already used by {other.name}")
    # contrast of every part against what it sits on, light and dark
    light, dark = colours(spec)
    for p in parts:
        if not p.on:
            continue
        for mode, pal, need in (("light", light, 1.35), ("dark", dark, 1.35)):
            c = contrast(pal[p.role], pal[p.on])
            if c < need:
                errs.append(f"{p.name}: {mode} contrast {c:.2f} against {p.on} (need {need})")
    # print
    pr = spec.print
    if pr.on != "ground" and pr.on not in names:
        errs.append(f"print sits on {pr.on!r}, which is not a part")
    for n in pr.clear:
        if n not in names:
            errs.append(f"clear zone for {n!r}, which is not a part")
    state = print_state(spec)
    if state not in ("current", "stale"):
        errs.append(state)
    src = json.load(open(SOURCES)).get(spec.name) if os.path.exists(SOURCES) else None
    if not src:
        errs.append("plate has no entry in brand/plates/sources.json")
    else:
        if not src["licence"].lower().startswith("public domain"):
            errs.append(f"plate licence is {src['licence']!r}, not public domain")
        if "Köhler" not in src["file"]:
            errs.append("plate is not from Köhler's Medizinal-Pflanzen")
    return errs, warn


# ------------------------------------------------------------------ render

RENDITIONS = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]


def ictool(doc, out, rendition, pts, scale):
    tool = ictool_path()
    if not tool:
        sys.exit("ictool not found: rendering needs Xcode 26+ (Icon Composer)")
    subprocess.run([tool, doc, "--export-image", "--output-file", out, "--platform", "macOS",
                    "--rendition", rendition, "--width", str(pts), "--height", str(pts),
                    "--scale", str(scale)], capture_output=True)


def icon_doc(app, docs=None):
    """Where an app's .icon lives: apps/<App>/AppIcon.icon, or <docs>/<App>.icon with --out."""
    if docs is None:
        return os.path.join(APPS, app, "AppIcon.icon")
    return docs if docs.endswith(".icon") else os.path.join(docs, f"{app}.icon")


def render(apps, out, docs=None):
    os.makedirs(out, exist_ok=True)
    from concurrent.futures import ThreadPoolExecutor
    jobs = []
    for app in apps:
        doc = icon_doc(app, docs)
        jobs += [(doc, os.path.join(out, f"{app}-{r}.png"), r, 256, 2) for r in RENDITIONS]
        jobs += [(doc, os.path.join(out, f"{app}-{r}-{pt}pt.png"), r, pt, 2)
                 for pt in (16, 32) for r in ("Default", "Dark")]
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda j: ictool(*j), jobs))
    sheet = os.path.join(out, "sheet.png")
    files = [os.path.join(out, f"{a}-{r}.png") for r in ("Default", "Dark") for a in apps]
    if shutil.which("montage"):
        subprocess.run(["montage", *files, "-tile", f"{len(apps)}x2", "-geometry", "200x200+8+8",
                        "-background", "#7a7a7a", "-font", "/System/Library/Fonts/Helvetica.ttc", sheet])
    return sheet


def construction(spec, out):
    """Flat drawing with the 64 grid, centre axes, 64/128 inset keylines and 256/384 circles on top."""
    light, _ = colours(spec)
    body = "".join(f'<g opacity="0.92">{p.svg.replace("#FFF", light[p.role])}</g>'
                   for p in reversed(spec.parts()))
    grid = "".join(f'<line x1="{v}" y1="0" x2="{v}" y2="1024"/><line x1="0" y1="{v}" x2="1024" y2="{v}"/>'
                   for v in range(64, 1024, 64))
    keys = ('<rect x="128" y="128" width="768" height="768" rx="128"/>'
            '<rect x="64" y="64" width="896" height="896" rx="192"/>'
            '<circle cx="512" cy="512" r="384"/><circle cx="512" cy="512" r="256"/>'
            '<line x1="512" y1="0" x2="512" y2="1024"/><line x1="0" y1="512" x2="1024" y2="512"/>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
           f'<defs><clipPath id="tile"><rect width="1024" height="1024" rx="256"/></clipPath></defs>'
           f'<g clip-path="url(#tile)"><rect width="1024" height="1024" fill="{spec.tile}"/>{body}'
           f'<g stroke="#FF2D8A" stroke-opacity="0.28" stroke-width="2">{grid}</g>'
           f'<g fill="none" stroke="#FF2D8A" stroke-opacity="0.85" stroke-width="4">{keys}</g></g></svg>')
    open(out, "w").write(svg)
    return out


# ------------------------------------------------------------------ plates

def search_plates(words):
    meta = json.load(open(INDEX))
    for title, m in meta.items():
        d = m["desc"]
        if all(w.lower() in d.lower() for w in words):
            plate = re.search(r"Plate ([^)]+)\)", title)
            print(f"{(plate.group(1) if plate else '?'):8} {m['w']}x{m['h']}  {d[:100]}\n         {title}")


def write_sources_md(specs):
    """brand/plates/SOURCES.md, from sources.json and each spec's plant name."""
    src = json.load(open(SOURCES)) if os.path.exists(SOURCES) else {}
    rows = []
    for app in sorted(src):
        e = src[app]
        plant = getattr(specs.get(app), "print", None)
        plant = plant.plant if plant and plant.plant else None
        name = f"{plant[0]} ({plant[1]})" if plant else ""
        number = re.search(r"Plate ([^)]+)\)", e["file"])
        label = f"Plate {number.group(1)}" if number else e["file"]
        rows.append(f"| {app} | {name} | [{label}]({e['page']}) | {e['credit']} | {e['licence']} |")
    text = (
        "# Botanical prints: sources\n\n"
        "All plates are from *Köhler's Medizinal-Pflanzen in naturgetreuen Abbildungen mit kurz erläuterndem Texte*\n"
        "(Franz Eugen Köhler, Gera-Untermhaus, 1887–1898), scanned by the Biodiversity Heritage Library and\n"
        "mirrored on Wikimedia Commons, where each file is marked public domain. Fetched and processed by\n"
        "`scripts/icons/herbarium.py` (`fetch`, then `build`); this file is generated from `sources.json`.\n"
        "Re-check each file's licence page before shipping.\n\n"
        "| App | Plant | Commons file | BHL source | Licence |\n|---|---|---|---|---|\n"
        + "\n".join(rows) + "\n")
    open(SOURCES_MD, "w", encoding="utf-8").write(text)
    return SOURCES_MD


def fetch_plate(app, title):
    meta = json.load(open(INDEX))
    m = meta.get(title) or meta.get("File:" + title)
    if not m:
        sys.exit(f"{title!r} is not in the Köhler index (herbarium.py plates <word>)")
    if not m["lic"].lower().startswith("public domain"):
        sys.exit(f"licence is {m['lic']!r}; only public-domain plates are allowed")
    ua = {"User-Agent": "slopapp-icons/1.0 (open-source; github.com/hunterunger/slopapp)"}
    os.makedirs(PLATES, exist_ok=True)
    out = os.path.join(PLATES, f"{app}.jpg")
    for attempt in range(8):
        try:
            data = urllib.request.urlopen(urllib.request.Request(m["url"], headers=ua), timeout=120).read()
            open(out, "wb").write(data)
            break
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(30 * (attempt + 1))
    src = json.load(open(SOURCES)) if os.path.exists(SOURCES) else {}
    src[app] = dict(file=title if title.startswith("File:") else "File:" + title, page=m["page"],
                    licence=m["lic"], credit=m["credit"], artist=m["artist"], date=m["date"],
                    description=m["desc"][:200], url=m["url"])
    json.dump(src, open(SOURCES, "w"), indent=1, ensure_ascii=False)
    write_sources_md(load_all()[0])
    print(f"{out}  ({m['w']}x{m['h']}, {m['lic']}); now set Print(crop=..., plant=...) in apps/{app}/Icon.py")


# ------------------------------------------------------------------ scaffolding

def free_tiles(specs):
    taken = {s.tile.upper(): n for n, s in specs.items()}
    return [k for k, v in TILES.items() if v.upper() not in taken], taken


def list_tiles():
    specs, _ = load_all()
    free, taken = free_tiles(specs)
    for k, v in TILES.items():
        print(f"{k:12} {v}  {taken.get(v.upper(), '(free)')}")
    if not free:
        print("\nEvery tile colour is taken: add a muted, natural colour to TILES in scripts/icons/herbarium.py.")


def new_spec(app):
    path = spec_path(app)
    if os.path.exists(path):
        sys.exit(f"{os.path.relpath(path, ROOT)} already exists")
    if not os.path.isdir(os.path.dirname(path)):
        sys.exit(f"no apps/{app}/ (scripts/new-app.sh creates it)")
    specs, _ = load_all()
    free, _ = free_tiles(specs)
    if not free:
        sys.exit("every TILES colour is taken: add a muted, natural colour to TILES in scripts/icons/herbarium.py")
    text = open(TEMPLATE, encoding="utf-8").read().replace("<App>", app).replace('TILES["sand"]', f'TILES["{free[0]}"]')
    open(path, "w", encoding="utf-8").write(text)
    print(f"{os.path.relpath(path, ROOT)}: tile {free[0]}. Draw it, pick a plate (herbarium.py plates <word>), "
          f"then herbarium.py check {app}")


# ------------------------------------------------------------------ cli

def load_all():
    """({app: spec} for every spec that loads, {app: error} for the rest)."""
    specs, broken = {}, {}
    for a in all_apps():
        try:
            specs[a] = load(a)
        except Exception as e:  # noqa: BLE001 - a spec someone is still writing
            broken[a] = f"{type(e).__name__}: {e}"
    return specs, broken


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    out = None
    if "--out" in args:
        i = args.index("--out")
        out, args = args[i + 1], args[:i] + args[i + 2:]
    if cmd == "plates":
        return search_plates(args)
    if cmd == "fetch":
        return fetch_plate(*args)
    if cmd == "new":
        return new_spec(*args)
    if cmd == "tiles":
        return list_tiles()
    if cmd not in ("check", "build", "render", "sources"):
        sys.exit(__doc__)
    specs, broken = load_all()
    if cmd == "sources":
        return print(write_sources_md(specs))
    apps = args or all_apps()
    for a in apps:
        if a not in specs and a not in broken:
            sys.exit(f"{a}: no {os.path.relpath(spec_path(a), ROOT)}")
    if cmd == "check":
        bad = 0
        for a in apps:
            if a in broken:
                print(f"{a}: FAIL\n  - Icon.py doesn't load: {broken[a]}")
                bad += 1
                continue
            errs, warn = check(specs[a], specs.values())
            if not errs and print_state(specs[a]) == "current" \
                    and read_tree(icon_doc(a, out)) != icon_files(specs[a]):
                state = "is out of date" if os.path.isdir(icon_doc(a, out)) else "is missing"
                warn.append(f"{os.path.relpath(icon_doc(a, out), ROOT)} {state} "
                            f"(herbarium.py build {a}, or scripts/bundle.sh {a})")
            print(f"{a}: {'ok' if not errs else 'FAIL'}")
            for e in errs:
                print(f"  - {e}")
            for w in warn:
                print(f"  ~ {w}")
            bad += bool(errs)
        sys.exit(1 if bad else 0)
    if out and out.endswith(".icon") and len(apps) != 1:
        sys.exit("--out <path>.icon needs exactly one app")
    written = 0
    for a in apps:
        if a in broken:
            sys.exit(f"{a}: Icon.py doesn't load: {broken[a]}")
        errs, _ = check(specs[a], specs.values())
        if errs:
            sys.exit(f"{a} fails the style check:\n  - " + "\n  - ".join(errs))
        written += write_icon(specs[a], icon_doc(a, out))
    where = out or "apps/<App>/AppIcon.icon"
    print(f"{len(apps)} icon(s), {written} rewritten, {len(apps) - written} up to date ({where})")
    if cmd == "render":
        print(render(apps, RENDERS, out))
        for a in apps:
            construction(specs[a], os.path.join(RENDERS, f"{a}-construction.svg"))


if __name__ == "__main__":
    main(sys.argv[1:])
