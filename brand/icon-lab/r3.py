#!/usr/bin/env python3
"""Round 3: "The tile is the thing", rebuilt on a construction system, in two finishes.

    python3 brand/icon-lab/r3.py            # both finishes + construction sheets

One drawing per app, built only from the tokens below; each finish (Glass, Nordic) maps the
drawing's colour roles and depth levels to colours and Icon Composer materials.

Construction (1024 canvas, the macOS tile fills it; its corner behaves like r = 256):
  grid       every coordinate is a multiple of U = 32 (asserted); layout snaps to M = 64
  strokes    W1 = 128 (tracks, handles, bodies)   W2 = 64 (text lines, rims)   H = 32 (cuts, slits)
  gap        G = 64 between neighbouring parts; inner padding P = 96 / 128
  corners    near the tile edge: r = 256 - inset (concentric with the mask)
             free shapes: pill (r = h/2) or r = 32 on small polygons; one radius family per icon
  bleed      shapes that run off the tile go to -64 / 1088
  angles     0, 45, 90 degrees only; curves are tangent arcs of one radius per icon
"""
import math, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import FLAVOURS, mix, c, gradient, svg_doc

U, M = 32, 64
W1, W2, H = 128, 64, 32
G = 64
TILE_R = 256
LAB = kit.LAB


def on_grid(*vals):
    for v in vals:
        assert abs(v / U - round(v / U)) < 1e-6, f"{v} is off the {U} grid"
    return vals


# ------------------------------------------------------------ primitives (white artwork)

def rect(x, y, w, h, r=0):
    on_grid(x, y, w, h)
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#FFF"/>'

def pill(x, y, w, h):
    return rect(x, y, w, h, min(w, h) / 2)

def disc(cx, cy, r):
    on_grid(cx, cy, r)
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF"/>'

def ring(cx, cy, r, w):
    """Ring with outer radius r and width w (hole shows what is below)."""
    on_grid(cx, cy, r, w)
    r2 = r - w
    return (f'<path fill="#FFF" fill-rule="evenodd" d="M{cx - r},{cy}a{r},{r} 0 1,0 {2 * r},0'
            f'a{r},{r} 0 1,0 {-2 * r},0zM{cx - r2},{cy}a{r2},{r2} 0 1,0 {2 * r2},0'
            f'a{r2},{r2} 0 1,0 {-2 * r2},0z"/>')

def stroke(d, w):
    return (f'<path d="{d}" fill="none" stroke="#FFF" stroke-width="{w}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>')

def rpoly(pts, r=32):
    """Convex polygon with every corner rounded to r: offset the outline inwards by r, then
    fill + stroke it 2r wide with round joins, which lands exactly on the original outline."""
    for p in pts:
        on_grid(*p)
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    s = 1 if area > 0 else -1  # inward normal side
    lines = []
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        nx, ny = -dy / L * s, dx / L * s
        lines.append(((x1 + nx * r, y1 + ny * r), (dx, dy)))
    inner = []
    for i in range(n):
        (p, d1), (q, d2) = lines[i - 1], lines[i]
        den = d1[0] * d2[1] - d1[1] * d2[0]
        t = ((q[0] - p[0]) * d2[1] - (q[1] - p[1]) * d2[0]) / den
        inner.append((p[0] + d1[0] * t, p[1] + d1[1] * t))
    d = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in inner) + " Z"
    return (f'<path d="{d}" fill="#FFF" stroke="#FFF" stroke-width="{2 * r}" '
            f'stroke-linejoin="round"/>')

def rot(body, x, y, deg):
    on_grid(x, y)
    return f'<g transform="translate({x} {y}) rotate({deg})">{body}</g>'

def cut(body, holes, mid):
    """body with holes (white artwork in `holes` becomes transparent)."""
    black = holes.replace('fill="#FFF"', 'fill="#000"').replace('stroke="#FFF"', 'stroke="#000"')
    return (f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="-200" y="-200" width="1424" height="1424">'
            f'<rect x="-200" y="-200" width="1424" height="1424" fill="#FFF"/>{black}</mask>'
            f'<g mask="url(#{mid})">{body}</g>')


# ------------------------------------------------------------ drawings
# Each returns a list of parts: (name, svg, role, depth). depth 0 = front.
# Roles: surface (big sheets), base (light objects), muted, main, main2 (light), main3 (deep),
#        accent, ink.

def clips():
    return [
        ("clip", cut(rect(320, -128, 384, 384, 128), pill(416, 96, 192, 64), "slot"), "accent", 0),
        ("card1", pill(256, 352, 512, 128), "main", 1),
        ("cards", pill(256, 544, 512, 128) + pill(256, 736, 512, 128), "muted", 1),
        ("sheet", rect(128, 192, 768, 960, 128), "surface", 2),
    ]

def snapper():
    cx, cy = 512, 544
    return [
        ("glint", disc(448, 480, 32), "base", 0),
        ("glass", disc(cx, cy, 192), "ink", 0),
        ("rim", ring(cx, cy, 320, 64), "base", 1),
        ("barrel", disc(cx, cy, 256), "main3", 1),
        ("shutter", rect(160, -64, 192, 160, 64), "accent", 2),
        ("flash", pill(672, 128, 192, 96), "base", 2),
        ("band", rect(-64, 416, 1152, 256), "main3", 2),
    ]

def bend_route(x0, y0, y1, R=256):
    """Transit-map route from (x0, y0) heading east to the line y = y1: a 45-degree arc of radius
    R, a 45-degree diagonal, a 45-degree arc back to east, then straight off the tile."""
    s = -1 if y1 < y0 else 1           # -1 = up
    k = math.sqrt(0.5)
    p1 = (x0 + k * R, y0 + s * (R - k * R))
    dy = abs(y1 - y0) - 2 * (R - k * R)
    q = (p1[0] + dy, p1[1] + s * dy)
    e = (q[0] + k * R, y1)
    sw1, sw2 = (0, 1) if s < 0 else (1, 0)
    return (f"M{x0},{y0} A{R},{R} 0 0 {sw1} {p1[0]:.2f},{p1[1]:.2f} L{q[0]:.2f},{q[1]:.2f} "
            f"A{R},{R} 0 0 {sw2} {e[0]:.2f},{e[1]:.2f} L1088,{y1}")

def switchboard():
    # one track in, a symmetric fork out; the lit route goes up. Bends: r = 256, like Commit.
    y0, jx = 512, 256
    return [
        ("switch", disc(jx, y0, 128), "accent", 0),
        ("lit", stroke(f"M-64,{y0} L{jx},{y0}", W1) + stroke(bend_route(jx, y0, 192), W1), "base", 1),
        ("unlit", stroke(bend_route(jx, y0, 832), W1), "muted", 2),
    ]


def paper():
    sheet = rpoly([(-64, 128), (640, 128), (896, 384), (896, 1088), (-64, 1088)], 32)
    flap = rpoly([(640, 128), (896, 384), (640, 384)], 32)
    lines = pill(128, 256, 320, 64) + pill(128, 384, 512, 64) + pill(128, 512, 576, 64) + \
        pill(128, 640, 384, 64)
    # pen in its own frame: tip at the origin, body running down +y, then turned -45 degrees
    pen = (rpoly([(0, 0), (64, 192), (-64, 192)], 32) + rect(-64, 192, 128, 832, 32))
    nib = rpoly([(0, 0), (32, 96), (-32, 96)], 16)
    return [
        ("nib", rot(nib, 576, 672, -45), "ink", 0),
        ("pen", rot(pen, 576, 672, -45), "accent", 0),
        ("lines", lines, "main2", 1),
        ("flap", flap, "muted", 1),
        ("sheet", sheet, "surface", 2),
    ]

def tidy():
    vx, vy = 512, -424  # vanishing point of the bristle block's sides
    slits = "".join(
        f'<path d="M{vx},{vy} L{x + (x - vx) * (1088 - 416) / (416 - vy):.1f},1088" stroke="#FFF" '
        f'stroke-width="{H}"/>' for x in (320, 448, 576, 704))
    block = rpoly([(192, 416), (832, 416), (1088, 1088), (-64, 1088)], 32)
    bristles = cut(block, slits + rect(-64, 352, 1152, 128), "slits")
    return [
        ("handle", rect(448, -64, 128, 384, 64), "accent", 0),
        ("ferrule", rect(192, 288, 640, 128, 64), "base", 0),
        ("bristles", bristles, "main2", 1),
    ]

def commit():
    x, r = 384, 256
    branch = f"M{x},832 L{x},{448 + r} A{r},{r} 0 0 1 {x + r},448 L1088,448"
    return [
        ("stations", ring(x, 192, 128, 64) + ring(x, 832, 128, 64) + ring(832, 448, 128, 64), "base", 0),
        ("branch", stroke(branch, W1), "accent", 1),
        ("main", stroke(f"M{x},-64 L{x},1088", W1), "muted", 2),
    ]

def awake():
    cx, cy = 448, 512
    return [
        ("coffee", disc(cx, cy, 256), "ink", 0),
        ("cup", ring(cx, cy, 320, 64) + pill(704, 448, 256, 128), "base", 1),
        ("saucer", disc(512, 512, 576), "main2", 2),
    ]

def dropper():
    # dropper in its own frame: tip at origin, body running up -y, turned 45 degrees
    body = rpoly([(0, 0), (64, -192), (-64, -192)], 32) + rect(-64, -448, 128, 288, 32)
    liquid = rpoly([(0, -64), (32, -192), (-32, -192)], 16) + rect(-32, -320, 64, 160, 32)
    bulb = pill(-128, -800, 256, 320)
    collar = rect(-128, -512, 256, 64, 32)
    tip = (384, 704)
    return [
        ("bulb", rot(bulb, *tip, 45), "accent", 0),
        ("collar", rot(collar, *tip, 45), "ink", 0),
        ("liquid", rot(liquid, *tip, 45), "accent", 0),
        ("tube", rot(body, *tip, 45), "base", 0),
        ("chip0", rect(192, 64, 192, 192, 32), "main2", 1),
        ("chip1", rect(192, 320, 192, 192, 32), "main", 1),
        ("chip2", rect(192, 576, 192, 192, 32), "accent", 1),
        ("chip3", rect(192, 832, 192, 192, 32), "main3", 1),
        ("strip", rect(128, -64, 320, 1152, 64), "surface", 2),
    ]

DRAW = dict(Clips=clips, Snapper=snapper, Switchboard=switchboard, Paper=paper, Tidy=tidy,
            Commit=commit, Awake=awake, Dropper=dropper)


# ------------------------------------------------------------ finishes

def deep(h, l=0.34, s=0.78):
    import colorsys
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue, _, sat = colorsys.rgb_to_hls(r, g, b)
    deg = hue * 360
    if 38 <= deg <= 75:
        deg = 30 + (deg - 38) * 0.15
    r, g, b = colorsys.hls_to_rgb(deg / 360, l, max(sat, s))
    return "#" + "".join(f"{round(x * 255):02X}" for x in (r, g, b))


def glass_palette(app):
    a = kit.APPS[app]
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    light = dict(surface="#FFFFFF", base="#FFFFFF", muted=mix(top, "#FFFFFF", 0.55),
                 main=mix(top, "#FFFFFF", 0.1), main2=mix(top, "#FFFFFF", 0.45),
                 main3=deep(bot, 0.4, 0.75), accent=pop, ink=deep(bot, 0.16, 0.6))
    dark = dict(surface="#3A3F48", base="#EEF0F3", muted=deep(top, 0.5, 0.55),
                main=deep(top, 0.6, 0.85), main2=deep(top, 0.42, 0.7),
                main3=deep(bot, 0.22, 0.7), accent=deep(pop, 0.6, 0.9), ink="#121418")
    if app == "Awake":
        light.update(main2=mix(pop, "#FFFFFF", 0.2), ink="#4A2213")
        dark.update(main2=deep(pop, 0.45, 0.85), ink="#2A140C")
    tile = gradient(mix(top, "#FFFFFF", 0.06), bot,
                    mix(deep(top, 0.40), "#30343B", 0.25), mix(deep(mix(top, bot, 0.5), 0.27), "#16181C", 0.3))
    return tile, light, dark


# Nordic: muted natural colours, warm whites, charcoal, matte.
BIRCH, OAT, CHAR, WALNUT = "#F5F0E8", "#E4D9C6", "#2F2D2A", "#5B4636"
NORDIC = {
    #             tile       main       main2      main3      accent     muted
    "Clips":       ("#D2A04C", "#B9473B", "#E9D2A6", "#8E6A2C", "#B9473B", "#E2C58E"),
    "Snapper":     ("#C4704F", "#C4704F", "#E5B9A4", "#8F4B33", "#E0B054", "#E8DCC8"),
    "Switchboard": ("#5D7E9A", "#5D7E9A", "#B8C8D5", "#3E5870", "#E0B054", "#93ABBE"),
    "Paper":       ("#8EA58B", "#8EA58B", "#B3C1AE", "#5D7459", "#C4704F", "#DDE3D6"),
    "Tidy":        ("#3F5E4E", "#3F5E4E", "#D8A84E", "#2A4236", "#C4704F", "#7E978A"),
    "Commit":      ("#8C7EA0", "#8C7EA0", "#C9BFD6", "#5F5274", "#E0B054", "#C3B8D2"),
    "Awake":       ("#A9665C", "#C98F86", "#D9A79E", "#8E5A52", "#B9473B", "#E6D7CF"),
    "Dropper":     ("#D9B8B0", "#C98F86", "#EBD6CF", "#8E5A52", "#4F7A72", "#F2E7E1"),
}

def nordic_palette(app):
    t, main, main2, main3, accent, muted = NORDIC[app]
    light = dict(surface=BIRCH, base=BIRCH, muted=muted, main=main, main2=main2, main3=main3,
                 accent=accent, ink=CHAR)
    night = "#24231F"
    dark = dict(surface="#3B3833", base="#E8E1D5", muted=mix(muted, night, 0.55), main=mix(main, "#FFFFFF", 0.08),
                main2=mix(main2, night, 0.45), main3=mix(main3, night, 0.35),
                accent=mix(accent, "#FFFFFF", 0.05), ink="#171614")
    if app == "Clips":
        light["main"] = dark["main"] = "#B9473B"
    if app == "Awake":
        light.update(ink=WALNUT)
        dark.update(ink="#2E241C")
    tile = gradient(mix(t, "#FFFFFF", 0.04), mix(t, CHAR, 0.06),
                    mix(t, night, 0.62), mix(t, night, 0.72))
    return tile, light, dark


def fill(light, dark):
    return {"fill-specializations": [{"value": {"solid": c(light)}},
                                     {"appearance": "dark", "value": {"solid": c(dark)}}]}


def assemble(app, palette, material):
    tile, light, dark = palette(app)
    parts = DRAW[app]()
    depths = sorted({p[3] for p in parts})
    groups, assets = [], {}
    for dpt in depths:
        layers = []
        for name, svg, role, d in parts:
            if d != dpt:
                continue
            assets[name] = svg_doc(svg)
            layers.append({"name": name, "image-name": f"{name}.svg", "glass": material["glass"],
                           "position": {"scale": 1, "translation-in-points": [0, 0]},
                           **fill(light[role], dark[role])})
        groups.append(material["group"](dpt, len(depths)))
        groups[-1]["layers"] = layers
    return tile, groups, assets


def glass_group(depth, n):
    g = {"shadow": {"kind": "neutral", "opacity": 0.5 if depth < n - 1 else 0.35},
         "translucency": {"enabled": True, "value": 0.2}, "specular": True}
    if depth == 0:
        g["refractivity"] = {"enabled": True, "strength": 0.6, "depth": 0.5}
    return g


def nordic_group(depth, n):
    return {"shadow": {"kind": "neutral", "opacity": 0.18 if depth < n - 1 else 0.1},
            "translucency": {"enabled": False, "value": 0.5}, "specular": False}


FINISHES = {
    "R3-Glass": (glass_palette, {"glass": True, "group": glass_group}),
    "R3-Nordic": (nordic_palette, {"glass": False, "group": nordic_group}),
}


# ------------------------------------------------------------ construction sheet

def construction(app, out):
    """Flat drawing (Nordic light colours, translucent) with the grid and keylines on top."""
    tile, light, _ = nordic_palette(app)
    parts = DRAW[app]()
    body = "".join(
        f'<g opacity="0.92" style="color:{light[role]}">{svg.replace("#FFF", light[role])}</g>'
        for name, svg, role, d in reversed(parts))
    grid = "".join(f'<line x1="{v}" y1="0" x2="{v}" y2="1024"/><line x1="0" y1="{v}" x2="1024" y2="{v}"/>'
                   for v in range(64, 1024, 64))
    keys = ('<rect x="128" y="128" width="768" height="768" rx="128"/>'
            '<rect x="64" y="64" width="896" height="896" rx="192"/>'
            '<circle cx="512" cy="512" r="384"/><circle cx="512" cy="512" r="256"/>'
            '<line x1="512" y1="0" x2="512" y2="1024"/><line x1="0" y1="512" x2="1024" y2="512"/>')
    t = NORDIC[app][0]
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
           f'<defs><clipPath id="tile"><rect width="1024" height="1024" rx="256"/></clipPath></defs>'
           f'<g clip-path="url(#tile)"><rect width="1024" height="1024" fill="{t}"/>{body}'
           f'<g stroke="#FF2D8A" stroke-opacity="0.28" stroke-width="2">{grid}</g>'
           f'<g fill="none" stroke="#FF2D8A" stroke-opacity="0.85" stroke-width="4">{keys}</g></g>'
           f'<rect width="1024" height="1024" rx="256" fill="none" stroke="#0006" stroke-width="2"/></svg>')
    open(out + ".svg", "w").write(svg)
    html = out + ".html"
    open(html, "w").write(f"<html><body style='margin:0;background:transparent'>"
                          f"<img src='{os.path.basename(out)}.svg' width='384' height='384'></body></html>")
    subprocess.run([kit.CHROME, "--headless=new", "--hide-scrollbars", "--window-size=384,384",
                    "--force-device-scale-factor=2", "--default-background-color=00000000",
                    "--allow-file-access-from-files", f"--screenshot={out}.png", f"file://{html}"],
                   capture_output=True)


if __name__ == "__main__":
    for key, (pal, mat) in FINISHES.items():
        kit.build(key, lambda app, a, pal=pal, mat=mat: assemble(app, pal, mat))
        print(kit.big_sheet(key))
    cdir = os.path.join(LAB, "construction")
    os.makedirs(cdir, exist_ok=True)
    for app in DRAW:
        construction(app, os.path.join(cdir, app))
    print("construction ->", cdir)
