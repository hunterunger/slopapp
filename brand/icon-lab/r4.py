#!/usr/bin/env python3
"""Round 4: Nordic + pattern and texture.

    python3 brand/icon-lab/r4.py

Same drawings as r3 (r3.DRAW), Nordic palette, plus:
  pattern  one per icon, on the icon's main surface, tone-on-tone (about 12% darker or lighter
           than the surface it sits on), aligned to the same 32/64 grid; line weights 8/16
  grain    one shared, fine speckle over the whole icon (two transparent PNG layers: dark flecks
           and light flecks), the same for every app
"""
import math, os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, lab, r3
from r3 import rect, pill, disc, ring, stroke, rpoly, rot, cut, BIRCH, CHAR, NORDIC
from kit import mix, c, svg_doc

LAB = kit.LAB
GRAIN = os.path.join(LAB, "grain")


# ------------------------------------------------------------ pattern primitives (white artwork)

def lines_v(pitch, w, x0=0, y0=-64, y1=1088):
    return "".join(f'<rect x="{x - w / 2}" y="{y0}" width="{w}" height="{y1 - y0}" fill="#FFF"/>'
                   for x in range(x0, 1089, pitch))

def lines_h(pitch, w, y0=0, x0=-64, x1=1088):
    return "".join(f'<rect x="{x0}" y="{y - w / 2}" width="{x1 - x0}" height="{w}" fill="#FFF"/>'
                   for y in range(y0, 1089, pitch))

def diagonal(pitch, w):
    """45-degree pinstripe: lines x + y = k * pitch (pitch measured along an edge)."""
    return "".join(f'<path d="M{k - 1152},1152 L{k},0" stroke="#FFF" stroke-width="{w}"/>'
                   for k in range(0, 2304, pitch))

def dot_grid(pitch, r, off=0, stagger=False):
    out = []
    for j, y in enumerate(range(off, 1089, pitch)):
        dx = pitch // 2 if stagger and j % 2 else 0
        out += [f'<circle cx="{x + dx}" cy="{y}" r="{r}" fill="#FFF"/>' for x in range(off - pitch, 1089, pitch)]
    return "".join(out)

def herringbone(col=64, row=32, w=10):
    out = []
    for i, x in enumerate(range(0, 1089, col)):
        for y in range(-row, 1089, row):
            a, b = ((x, y), (x + col, y + col // 2)) if i % 2 == 0 else ((x, y + col // 2), (x + col, y))
            out.append(f'<path d="M{a[0]},{a[1]} L{b[0]},{b[1]}" stroke="#FFF" stroke-width="{w}" '
                       f'stroke-linecap="butt"/>')
    return "".join(out)

def rings_at(cx, cy, r0, r1, step, w):
    return "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#FFF" stroke-width="{w}"/>'
                   for r in range(r0, r1, step))

def masked(pattern, shape, mid):
    """pattern clipped to shape (shape is white artwork)."""
    return (f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424">'
            f'{shape}</mask><g mask="url(#{mid})">{pattern}</g>')


# ------------------------------------------------------------ patterns per app
# Each returns (name, svg, tone, depth, before) where `tone` = (role, amount): amount < 0 darkens,
# > 0 lightens the role's colour; `before` = name of the part it sits on (inserted in front of it),
# or None to sit at the very back of its depth (on the tile).

def p_clips():   # ticking stripe on the clipboard cover
    return [("ticking", lines_v(64, 16, 32), ("tile", -0.16), 2, None)]

def p_snapper():  # pebbled grip on the band
    return [("pebble", masked(dot_grid(32, 7, 16, stagger=True), rect(-64, 416, 1152, 256), "band"),
             ("main3", +0.14), 2, "band")]

def p_switchboard():  # diagonal pinstripe ground
    return [("pinstripe", diagonal(64, 14), ("tile", -0.12), 2, None)]

def p_paper():  # birch desk grain
    return [("grain", rings_at(-320, 1344, 640, 2600, 56, 10), ("tile", -0.13), 2, None)]

def p_tidy():  # straw in the bristles
    vx, vy = 512, -424
    slits = (320, 448, 576, 704)
    xs = [x for x in range(200, 830, 20) if min(abs(x - s) for s in slits) > 30]
    straws = "".join(
        f'<path d="M{vx},{vy} L{x + (x - vx) * (1088 - 416) / (416 - vy):.1f},1088" stroke="#FFF" '
        f'stroke-width="6"/>' for x in xs)
    block = rpoly([(192, 480), (832, 480), (1088, 1088), (-64, 1088)], 32)
    return [("straw", masked(straws, block, "blk"), ("main2", -0.2), 1, "bristles")]

def p_commit():  # map dot grid
    return [("mapdots", dot_grid(64, 9, 32), ("tile", -0.14), 2, None)]

def p_awake():  # gingham tablecloth + a glaze band on the saucer
    return [("glaze", ring(512, 512, 416, 32), ("main2", -0.14), 2, "saucer"),
            ("ging_v", lines_v(128, 64, 64), ("tile", -0.13), 2, None),
            ("ging_h", lines_h(128, 64, 64), ("tile", -0.13), 2, None)]

def p_dropper():  # tweed herringbone ground
    return [("tweed", herringbone(64, 32, 10), ("tile", -0.12), 2, None)]

PATTERNS = dict(Clips=p_clips, Snapper=p_snapper, Switchboard=p_switchboard, Paper=p_paper,
                Tidy=p_tidy, Commit=p_commit, Awake=p_awake, Dropper=p_dropper)


def awake_parts():
    """Awake on a gingham tablecloth: the cloth is the tile, the saucer sits inside it (r 448)."""
    parts = r3.DRAW["Awake"]()
    return [p if p[0] != "saucer" else ("saucer", disc(512, 512, 448), p[2], p[3]) for p in parts]


def parts_for(app):
    parts = awake_parts() if app == "Awake" else r3.DRAW[app]()
    parts = [(n, s, r, d, None) for n, s, r, d in parts]
    for name, svg, tone, depth, before in PATTERNS[app]():
        item = (name, svg, tone, depth, True)
        if before:
            i = next(i for i, p in enumerate(parts) if p[0] == before)
            parts.insert(i, item)
        else:
            parts.append(item)
    return parts


# ------------------------------------------------------------ grain

def make_grain():
    """Two 1024 PNGs of transparent flecks (dark, light), 2 px grain at 1024."""
    os.makedirs(GRAIN, exist_ok=True)
    for name, colour, seed in (("fleck-dark", "black", 3), ("fleck-light", "white", 9)):
        a = os.path.join(GRAIN, f"{name}-alpha.png")
        subprocess.run(["magick", "-size", "512x512", "xc:gray50", "-seed", str(seed), "-attenuate", "1.4",
                        "+noise", "Gaussian", "-colorspace", "gray", "-fx", "abs(u-0.5)*2",
                        "-level", "35%,100%", "-filter", "point", "-resize", "1024x1024", a], check=True)
        subprocess.run(["magick", "-size", "1024x1024", f"xc:{colour}", a, "-alpha", "off",
                        "-compose", "CopyOpacity", "-composite", os.path.join(GRAIN, f"{name}.png")],
                       check=True)


def grain_group(strength=1.0):
    return {"layers": [
        {"name": "fleck-light", "image-name": "fleck-light.png", "glass": False,
         "opacity-specializations": [{"value": 0.10 * strength}, {"appearance": "dark", "value": 0.16 * strength}]},
        {"name": "fleck-dark", "image-name": "fleck-dark.png", "glass": False,
         "opacity-specializations": [{"value": 0.30 * strength}, {"appearance": "dark", "value": 0.22 * strength}]},
    ], "shadow": {"kind": "none", "opacity": 0}, "specular": False,
        "translucency": {"enabled": False, "value": 0.5}}


# ------------------------------------------------------------ assemble

def tone(colour, amount):
    return mix(colour, CHAR if amount < 0 else BIRCH, abs(amount))


def palette(app):
    tile, light, dark = r3.nordic_palette(app)
    t = NORDIC[app][0]
    light["tile"], dark["tile"] = t, mix(t, "#24231F", 0.66)
    return tile, light, dark


def assemble(app, grain=1.0):
    tile, light, dark = palette(app)
    parts = parts_for(app)
    depths = sorted({p[3] for p in parts})
    groups, assets = [], {}
    if grain:
        groups.append(grain_group(grain))
        assets["fleck-light.png"] = os.path.join(GRAIN, "fleck-light.png")
        assets["fleck-dark.png"] = os.path.join(GRAIN, "fleck-dark.png")
    for dpt in depths:
        layers = []
        for name, svg, role, d, is_pattern in parts:
            if d != dpt:
                continue
            assets[name] = svg_doc(svg)
            if is_pattern:
                rname, amt = role
                lc, dc = tone(light[rname], amt), mix(dark[rname], "#FFFFFF" if amt < 0 else "#000000", 0.07)
            else:
                lc, dc = light[role], dark[role]
            layers.append({"name": name, "image-name": f"{name}.svg", "glass": False,
                           "position": {"scale": 1, "translation-in-points": [0, 0]},
                           **r3.fill(lc, dc)})
        g = r3.nordic_group(dpt, len(depths))
        g["layers"] = layers
        groups.append(g)
    return tile, groups, assets


def write_doc(path, background, groups, assets):
    """lab.write_doc, but assets ending in .png are copied files."""
    import json, shutil
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(os.path.join(path, "Assets"))
    for name, data in assets.items():
        if name.endswith(".png"):
            shutil.copy(data, os.path.join(path, "Assets", name))
        else:
            open(os.path.join(path, "Assets", f"{name}.svg"), "w").write(data)
    doc = dict(background)
    doc["groups"] = groups
    doc["supported-platforms"] = {"squares": "shared"}
    json.dump(doc, open(os.path.join(path, "icon.json"), "w"), indent=2)


kit.write_doc = write_doc

if __name__ == "__main__":
    make_grain()
    kit.build("R4-Texture", lambda app, a: assemble(app, 1.0))
    print(kit.big_sheet("R4-Texture"))
