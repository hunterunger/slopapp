#!/usr/bin/env python3
"""Round 5: Nordic + botanical prints (Köhler's Medizinal-Pflanzen, 1887-1898, public domain, via BHL).

    python3 brand/icon-lab/r5.py

Same drawings as r3 (Nordic palette). One engraving per app, turned into a one-colour print
(paper -> transparent, ink density -> opacity), embedded in an SVG layer and clipped by a vector
mask, so textured and flat areas meet on a crisp edge. Nothing else is textured.

  N-Ground   the print fills the tile; every object sits on it flat
  O-Inlay    the tile is flat; the print fills one surface of the object (sheet, saucer, band...)

Print tone: the surface colour, 30% toward charcoal (light) or 16% toward white (dark).
"""
import base64, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, r3
from r3 import rect, pill, disc, ring, stroke, rpoly, BIRCH, CHAR, NORDIC
from kit import mix, svg_doc

LAB = kit.LAB
BHL = os.path.join(LAB, "bhl")

# Plate crops: (x, y, size) of a square in the plate's pixels, plus erase boxes [(x, y, w, h)] in the
# same pixels (labels, dissection figures), and an optional flip.
PLATES = {
    "Awake":       dict(crop=(80, 100, 1200), erase=[(1000, 60, 375, 140), (0, 1050, 280, 500)]),
    "Dropper":     dict(crop=(300, 300, 1100), erase=[(800, 280, 620, 180)]),
    "Paper":       dict(crop=(450, 60, 950), erase=[]),
    "Commit":      dict(crop=(330, 450, 1050), erase=[(1080, 450, 320, 300)]),
    "Switchboard": dict(crop=(380, 450, 1000), erase=[]),
    "Tidy":        dict(crop=(100, 40, 1150), erase=[(900, 0, 574, 240)]),
    "Clips":       dict(crop=(260, 470, 940), erase=[(1080, 400, 320, 520)]),
    "Snapper":     dict(crop=(250, 150, 1000), erase=[(1150, 0, 300, 1300)]),
}

def halo(svg, pad=32):
    """Black knock-out version of white artwork, grown by `pad` on every side (for print masks)."""
    import re
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


# Rule: anything sitting on a printed surface gets a 32-unit clear zone around it.
def knockouts(app, parts):
    names = {"Clips": ["card1", "cards"], "Paper": ["lines"], "Awake": ["cup"]}.get(app, [])
    return "".join(halo(s) for n, s, *_ in parts if n in names)


# Which part carries the print in O-Inlay, and the mask for it (white artwork).
def inlay_target(app):
    T = {
        "Clips": ("sheet", rect(128, 192, 768, 960, 128)),
        "Snapper": ("band", rect(-64, 416, 1152, 256)),
        "Switchboard": ("lit", None),
        "Paper": ("sheet", None),
        "Tidy": ("bristles", rpoly([(192, 480), (832, 480), (1088, 1088), (-64, 1088)], 32) +
                 "".join(f'<path d="M512,-424 L{x + (x - 512) * (1088 - 416) / (416 + 424):.1f},1088" '
                         f'stroke="#000" stroke-width="32"/>' for x in (320, 448, 576, 704))),
        "Commit": ("main", None),
        "Awake": ("saucer", disc(512, 512, 448)),
        "Dropper": ("strip", rect(128, -64, 320, 1152, 64)),
    }
    return T[app]


def print_png(app):
    """Processed print: white with alpha = ink density, 1024 square."""
    out = os.path.join(BHL, "tex", f"{app}.png")
    if os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(__file__):
        return out
    p = PLATES[app]
    x, y, s = p["crop"]
    src = os.path.join(BHL, "raw", f"{app}.jpg")
    alpha = os.path.join(BHL, "tex", f"{app}-alpha.png")
    if p.get("erase"):  # paint over labels/figures with paper colour (separate step: IM blanks
        clean = os.path.join(BHL, "tex", f"{app}-clean.png")  # the image if draw+resize share a command)
        cmd = ["magick", src, "-fill", "#FFFFFF"]
        for ex, ey, ew, eh in p["erase"]:
            cmd += ["-draw", f"rectangle {ex},{ey} {ex + ew},{ey + eh}"]
        subprocess.run(cmd + [clean], check=True)
        src = clean
    cmd = ["magick", src, "-alpha", "off", "-crop", f"{s}x{s}+{x}+{y}", "+repage"]
    if p.get("flip"):
        cmd += ["-flop"]
    # white point just under this plate's paper tone, so bare paper is fully transparent
    paper = float(subprocess.run(["magick", src, "-alpha", "off", "-colorspace", "gray", "-format",
                                  "%[fx:median]", "info:"], capture_output=True, text=True).stdout)
    wp = max(60, min(92, paper * 100 - 6))
    cmd += ["-colorspace", "gray", "-level", f"18%,{wp:.0f}%", "-negate", "-resize", "1024x1024!", alpha]
    subprocess.run(cmd, check=True)
    subprocess.run(["magick", "-size", "1024x1024", "xc:white", alpha, "-alpha", "off", "-compose",
                    "CopyOpacity", "-composite", "-define", "png:color-type=4", out], check=True)
    return out


def print_svg(app, mask=None, mid="m"):
    b64 = base64.b64encode(open(print_png(app), "rb").read()).decode()
    img = (f'<image x="0" y="0" width="1024" height="1024" '
           f'xlink:href="data:image/png;base64,{b64}"/>')
    if mask:
        img = (f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424">'
               f'{mask}</mask><g mask="url(#{mid})">{img}</g>')
    return img


def svg_doc_x(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>')


def parts_for(app):
    parts = r3.DRAW[app]()
    if app == "Awake":  # cup on a saucer on the tile (the tile shows around it)
        parts = [p if p[0] != "saucer" else ("saucer", disc(512, 512, 448), p[2], p[3]) for p in parts]
    return parts


# The rule for the mixed set: the print goes on the icon's largest uninterrupted surface.
PRINTED = {"Clips": "inlay", "Paper": "inlay", "Awake": "inlay", "Tidy": "inlay",
           "Snapper": "ground", "Switchboard": "ground", "Commit": "ground", "Dropper": "ground"}


def assemble(app, mode):
    if mode == "mix":
        mode = PRINTED[app]
    tile, light, dark = r3.nordic_palette(app)
    t = NORDIC[app][0]
    light["tile"], dark["tile"] = t, mix(t, "#24231F", 0.66)
    parts = [(n, s, r, d, False) for n, s, r, d in parts_for(app)]
    if mode == "ground":
        parts.append(("print", print_svg(app), "tile", max(p[3] for p in parts), True))
    else:
        target, mask = inlay_target(app)
        i = next(i for i, p in enumerate(parts) if p[0] == target)
        mask = (mask or parts[i][1]) + knockouts(app, parts)
        parts.insert(i, ("print", print_svg(app, mask), parts[i][2], parts[i][3], True))
    depths = sorted({p[3] for p in parts})
    groups, assets = [], {}
    for dpt in depths:
        layers = []
        for name, svg, role, d, is_print in parts:
            if d != dpt:
                continue
            if is_print:
                assets[name] = svg_doc_x(svg)
                if role in ("surface", "base"):  # birch: print in the app's own colour
                    lc, dc = mix(light[role], light["tile"], 0.5), mix(dark[role], "#FFFFFF", 0.14)
                else:  # coloured surface: tone-on-tone
                    lc, dc = mix(light[role], CHAR, 0.30), mix(dark[role], "#FFFFFF", 0.16)
            else:
                assets[name] = svg_doc(svg)
                lc, dc = light[role], dark[role]
            layers.append({"name": name, "image-name": f"{name}.svg", "glass": False,
                           "position": {"scale": 1, "translation-in-points": [0, 0]}, **r3.fill(lc, dc)})
        g = r3.nordic_group(dpt, len(depths))
        g["layers"] = layers
        groups.append(g)
    return tile, groups, assets


if __name__ == "__main__":
    os.makedirs(os.path.join(BHL, "tex"), exist_ok=True)
    only = sys.argv[1:] or ["ground", "inlay", "mix"]
    for mode in only:
        key = {"ground": "R5-Ground", "inlay": "R5-Inlay", "mix": "R5-Mix"}[mode]
        kit.build(key, lambda app, a, mode=mode: assemble(app, mode))
        print(kit.big_sheet(key))
