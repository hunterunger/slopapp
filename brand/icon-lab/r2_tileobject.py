#!/usr/bin/env python3
"""Round 2, direction "The tile is the thing": the whole square is the object, edges bleed off.

    python3 brand/icon-lab/r2_tileobject.py

Each app is a small set of flat, one-colour layers (drawn here on the 1024 canvas). Colour comes
from the layer fill, so every asset is plain white artwork.
"""
import colorsys, math
import kit
from kit import FLAVOURS, GRAPHITE, mix, c, gradient, group, svg_doc

KEY = "R2-TileObject"
WHITE, NIGHT = "#FFFFFF", "#3A3F48"


# ------------------------------------------------------------ colour

def deep(h, light=0.34, sat=0.78):
    """Dark-mode version of a flavour: same hue, lower lightness, saturation kept (jewel, not mud).
    Yellows slide toward amber so they don't go olive."""
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue, l, s = colorsys.rgb_to_hls(r, g, b)
    deg = hue * 360
    if 38 <= deg <= 75:
        deg = 30 + (deg - 38) * 0.15
    r, g, b = colorsys.hls_to_rgb(deg / 360, light, max(s, sat))
    return "#" + "".join(f"{round(x * 255):02X}" for x in (r, g, b))


def pale(h, t=0.55):
    return mix(h, WHITE, t)


def tile(a):
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    # dark: same hues, deeper, saturation held back so blues and purples stay jewel, not neon
    return gradient(mix(top, WHITE, 0.06), bot, mix(deep(top, 0.40), "#30343B", 0.25),
                    mix(deep(mix(top, bot, 0.5), 0.27), "#16181C", 0.3))


# ------------------------------------------------------------ layers

class Doc:
    """Collects groups (front first) and their assets."""

    def __init__(self, bg):
        self.bg, self.groups, self.assets = bg, [], {}

    def group(self, layers, **kw):
        self.groups.append(group(layers, **kw))

    def layer(self, name, body, light, dark=None, opacity=None, glass=True):
        self.assets[name] = svg_doc(body)
        spec = [{"value": {"solid": c(light)}}]
        if dark:
            spec.append({"appearance": "dark", "value": {"solid": c(dark)}})
        d = {"name": name, "image-name": f"{name}.svg", "glass": glass,
             "position": {"scale": 1, "translation-in-points": [0, 0]},
             "fill-specializations": spec}
        if opacity is not None:
            d["opacity"] = opacity
        return d

    def out(self):
        return self.bg, self.groups, self.assets


def rect(x, y, w, h, r=0, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#FFF" {extra}/>'


def circ(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF"/>'


def ring(cx, cy, r1, r2):
    return (f'<path fill="#FFF" fill-rule="evenodd" d="M{cx - r1},{cy}a{r1},{r1} 0 1,0 {2 * r1},0'
            f'a{r1},{r1} 0 1,0 {-2 * r1},0z M{cx - r2},{cy}a{r2},{r2} 0 1,0 {2 * r2},0'
            f'a{r2},{r2} 0 1,0 {-2 * r2},0z"/>')


def line(d, w, cap="round"):
    return (f'<path d="{d}" fill="none" stroke="#FFF" stroke-width="{w}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round"/>')


# ------------------------------------------------------------ apps

def clips(a):
    """The tile is a clipboard: a sheet bleeding off the bottom, a big clip biting the top edge."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    clip = (rect(322, -80, 380, 330, 90) +
            f'<rect x="402" y="40" width="220" height="110" rx="40" fill="#000"/>')
    d.group([d.layer("clip", f'<mask id="m">{rect(0, 0, 1024, 1024)}'
                             f'<rect x="417" y="60" width="190" height="80" rx="40" fill="#000"/></mask>'
                             f'<g mask="url(#m)">{rect(322, -80, 380, 320, 96)}</g>',
                     pop, deep(pop, 0.62, 0.85))],
            shadow="layer-color", shadow_opacity=0.7, translucency=0.1)
    # clipped items on the sheet: three cards, the newest one in colour
    d.group([d.layer("card1", rect(230, 330, 564, 150, 48), pale(top, 0.0), deep(top, 0.6, 0.9)),
             d.layer("cards", rect(230, 530, 564, 150, 48) + rect(230, 730, 564, 150, 48),
                     pale(top, 0.62), "#4C525C")],
            shadow="neutral", shadow_opacity=0.3, translucency=0.15)
    d.group([d.layer("sheet", rect(150, 170, 724, 1000, 70), WHITE, NIGHT)],
            shadow="neutral", shadow_opacity=0.5, translucency=0.12)
    return d.out()


def snapper(a):
    """The tile is a camera front: a grip band across, a big glass lens, a flash."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    d.group([d.layer("iris", ring(512, 560, 130, 92), pale(top, 0.2), deep(top, 0.55, 0.7), opacity=0.8),
             d.layer("glass", circ(512, 560, 190), deep(bot, 0.22, 0.6), "#14161A")],
            shadow="neutral", shadow_opacity=0.4, translucency=0.25)
    d.group([d.layer("lens", ring(512, 560, 330, 270) + ring(512, 560, 250, 205), WHITE, "#E8E9EE")],
            shadow="neutral", shadow_opacity=0.55, translucency=0.15)
    d.group([d.layer("flash", rect(704, 120, 190, 110, 40), pop, deep(pop, 0.6, 0.9)),
             d.layer("band", rect(-40, 410, 1104, 300, 0), deep(bot, 0.42, 0.75), deep(bot, 0.2, 0.7))],
            shadow="neutral", shadow_opacity=0.35, translucency=0.1)
    return d.out()


def switchboard(a):
    """Thick tracks run edge to edge and split at a switch; the chosen route is lit."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    jx, jy = 400, 560
    d.group([d.layer("switch", circ(jx, jy, 132), pop, deep(pop, 0.6, 0.9))],
            shadow="layer-color", shadow_opacity=0.8, translucency=0.1)
    d.group([d.layer("lit", line(f"M-80,{jy} L{jx},{jy} C{jx + 200},{jy} 600,250 1120,250", 156),
                     WHITE, "#F1F2F5")],
            shadow="neutral", shadow_opacity=0.5, translucency=0.2)
    d.group([d.layer("unlit", line(f"M{jx},{jy} C{jx + 200},{jy} 600,850 1120,850", 156),
                     pale(bot, 0.45), deep(bot, 0.5, 0.6), opacity=0.9)],
            shadow="neutral", shadow_opacity=0.3, translucency=0.2)
    return d.out()


def paper(a):
    """The tile is a sheet with a dog-eared corner; a pen crosses it."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    # sheet covers the tile except the top-right corner; fold line from (560,-0) to (1024,464)
    fx, fy = 540, 484
    pen = ('<g transform="rotate(-45 512 512)"><path fill="#FFF" d="M300 430 L800 430 '
           'A75 75 0 0 1 800 580 L300 580 L160 505 Z"/></g>')
    d.group([d.layer("pen", pen, pop, deep(pop, 0.58, 0.9))],
            shadow="layer-color", shadow_opacity=0.7, translucency=0.1)
    d.group([d.layer("flap", f'<path d="M{fx},-40 L{fx},{fy} L1064,{fy} Z" fill="#FFF"/>',
                     pale(top, 0.55), deep(top, 0.55, 0.6)),
             d.layer("lines", rect(150, 300, 260, 64, 32) + rect(150, 440, 420, 64, 32) +
                     rect(150, 580, 300, 64, 32), pale(top, 0.35), deep(top, 0.55, 0.55))],
            shadow="neutral", shadow_opacity=0.35, translucency=0.1)
    d.group([d.layer("sheet", f'<path d="M-40,-40 L{fx},-40 L1064,{fy} L1064,1064 L-40,1064 Z" '
                              f'fill="#FFF"/>', WHITE, NIGHT)],
            shadow="neutral", shadow_opacity=0.5, translucency=0.1)
    return d.out()


def tidy(a):
    """A brush head: handle from the top edge, a wide head, bristles fanning off the bottom."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    bristles = ""
    n = 6
    for i in range(n):
        t = (i + 0.5) / n
        x0 = 200 + t * 624
        x1 = -120 + t * 1264
        w0, w1 = 40, 66
        bristles += (f'<path d="M{x0 - w0},560 L{x0 + w0},560 L{x1 + w1},1100 L{x1 - w1},1100 Z" '
                     f'fill="#FFF"/>')
    d.group([d.layer("band", rect(130, 425, 764, 64, 0), pale(bot, 0.1), deep(bot, 0.45, 0.7)),
             d.layer("head", rect(130, 330, 764, 250, 80), WHITE, "#ECEDF1")],
            shadow="neutral", shadow_opacity=0.55, translucency=0.15)
    d.group([d.layer("handle", rect(442, -80, 140, 460, 70), pop, deep(pop, 0.6, 0.9))],
            shadow="layer-color", shadow_opacity=0.6, translucency=0.1)
    d.group([d.layer("bristles", bristles, pale(pop, 0.3), deep(pop, 0.5, 0.8))],
            shadow="neutral", shadow_opacity=0.3, translucency=0.2)
    return d.out()


def commit(a):
    """A transit map: a main line runs top to bottom, a branch leaves it, stations at the joins."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    x = 360
    st = "".join(circ(cx, cy, 92) for cx, cy in [(x, 250), (x, 760), (720, 420)])
    holes = "".join(f'<circle cx="{cx}" cy="{cy}" r="42" fill="#000"/>' for cx, cy in [(x, 250), (x, 760), (720, 420)])
    d.group([d.layer("stations", f'<mask id="m">{rect(0, 0, 1024, 1024)}{holes}</mask>'
                                 f'<g mask="url(#m)">{st}</g>', WHITE, "#F1F2F5")],
            shadow="neutral", shadow_opacity=0.55, translucency=0.1)
    d.group([d.layer("branch", line(f"M{x},760 C{x},560 520,420 720,420 L1120,420", 116), pop,
                     deep(pop, 0.58, 0.9))],
            shadow="layer-color", shadow_opacity=0.7, translucency=0.15)
    d.group([d.layer("main", line(f"M{x},-80 L{x},1110", 116), pale(top, 0.55), deep(top, 0.62, 0.6))],
            shadow="neutral", shadow_opacity=0.35, translucency=0.2)
    return d.out()


def awake(a):
    """A coffee cup seen from above: saucer, rim, coffee, a handle off to the side."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    cx, cy = 470, 540
    d.group([d.layer("crema", ring(cx, cy, 232, 186), "#B5683A", "#8A4A26", opacity=0.9),
             d.layer("coffee", circ(cx, cy, 232), "#5B2A17", "#3A1A0E")],
            shadow="neutral", shadow_opacity=0.3, translucency=0.1)
    d.group([d.layer("cup", circ(cx, cy, 300) + rect(cx + 250, cy - 60, 250, 120, 60), WHITE, "#ECEDF1")],
            shadow="neutral", shadow_opacity=0.6, translucency=0.12)
    d.group([d.layer("saucer", circ(cx, cy, 440), pale(pop, 0.15), deep(pop, 0.5, 0.85), opacity=0.95)],
            shadow="layer-color", shadow_opacity=0.5, translucency=0.2)
    return d.out()


def dropper(a):
    """A paint-chip strip bleeding off top and bottom; a dropper lifts a colour from it."""
    top, bot, pop = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], FLAVOURS[a["pop"]]
    d = Doc(tile(a))
    chips = [FLAVOURS["grape"], FLAVOURS["bubblegum"], FLAVOURS["strawberry"], pop]
    tube = (f'<g transform="rotate(45 640 440)">'
            f'<rect x="580" y="140" width="120" height="430" rx="40" fill="#FFF"/>'
            f'<path d="M600 570 L680 570 L655 700 L625 700 Z" fill="#FFF"/></g>')
    bulb = '<g transform="rotate(45 640 440)"><rect x="560" y="-140" width="160" height="300" rx="80" fill="#FFF"/></g>'
    d.group([d.layer("bulb", bulb, pop, deep(pop, 0.6, 0.9)),
             d.layer("tube", tube, WHITE, "#ECEDF1")],
            shadow="neutral", shadow_opacity=0.55, translucency=0.15)
    layers = []
    for i, col in enumerate(chips):
        layers.append(d.layer(f"chip{i}", rect(140, -60 + i * 290, 330, 250, 36), col, deep(col, 0.5, 0.85)))
    d.group(layers, shadow="neutral", shadow_opacity=0.3, translucency=0.05)
    d.group([d.layer("strip", rect(100, -100, 410, 1224, 60), WHITE, NIGHT)],
            shadow="neutral", shadow_opacity=0.5, translucency=0.1)
    return d.out()


DRAW = dict(Clips=clips, Snapper=snapper, Switchboard=switchboard, Paper=paper, Tidy=tidy,
            Commit=commit, Awake=awake, Dropper=dropper)


def make(app, a):
    return DRAW[app](a)


if __name__ == "__main__":
    kit.build(KEY, make)
    print(kit.big_sheet(KEY))
