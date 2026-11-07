#!/usr/bin/env python3
"""Round 2, direction "Glass geometry": no line glyphs. Each icon is 2-4 big translucent candy shapes
that overlap and run off the tile edges. Shared grammar: circles, pills, quarter arcs, rounded rects;
three opacity steps; light from the top left. Colours come from each app's flavours (top/bottom/pop).

    python3 brand/icon-lab/r2_geometry.py
"""
import kit
from kit import FLAVOURS, GRAPHITE, mix, c, svg_doc, layer, group

# ---------------------------------------------------------------- shape vocabulary (white; the layer fill colours it)
W = "#FFFFFF"

def circle(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{W}"/>'

def ring(cx, cy, r, w):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{W}" stroke-width="{w}"/>'

def rrect(x, y, w, h, r, rot=0, ox=None, oy=None):
    ox = x + w / 2 if ox is None else ox
    oy = y + h / 2 if oy is None else oy
    t = f' transform="rotate({rot} {ox} {oy})"' if rot else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{W}"{t}/>'

def band(d, w):
    """A thick pill-ended stroke along a path."""
    return (f'<path d="{d}" fill="none" stroke="{W}" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')

def shape(d):
    return f'<path d="{d}" fill="{W}"/>'

def svg(*parts):
    return svg_doc("".join(parts))

# ---------------------------------------------------------------- colour + layering

STEPS = (0.96, 0.8, 0.64)  # front, middle, back opacity

def col(name):
    return FLAVOURS[name]

def fillspec(hexcol):
    """Light: the flavour. Dark: the same flavour, a touch brighter so it glows on graphite."""
    return {"fill-specializations": [
        {"value": {"solid": c(hexcol)}},
        {"appearance": "dark", "value": {"solid": c(mix(hexcol, "#FFFFFF", 0.12))}},
    ]}

def piece(name, hexcol, step, shadow=0.45, translucency=0.5):
    """One shape = one glass group, so overlaps mix colour through translucency."""
    return group([layer(name, glass=True, opacity=STEPS[step], fill=fillspec(hexcol))],
                 shadow="neutral", shadow_opacity=shadow, translucency=translucency)

def background(a):
    top, bot = col(a["top"]), col(a["bottom"])
    return {"fill-specializations": [
        {"value": {"linear-gradient": [c(mix(top, "#FFFFFF", 0.74)), c(mix(bot, "#FFFFFF", 0.58))]}},
        {"appearance": "dark", "value": {"linear-gradient": [c(mix("#2C3037", top, 0.22)),
                                                             c(mix("#111316", bot, 0.10))]}},
    ]}

# ---------------------------------------------------------------- compositions (groups listed front -> back)

def clips(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    # three cards fanned out of the bottom-right, plus the clip pill on the front card
    return [
        ("clip", p, 0, svg(rrect(330, 150, 300, 130, 65, -8, 480, 760))),
        ("front", t, 0, svg(rrect(200, 210, 560, 900, 96, -8, 480, 760))),
        ("middle", b, 1, svg(rrect(260, 180, 560, 900, 96, 6, 540, 760))),
        ("back", p, 2, svg(rrect(330, 160, 560, 900, 96, 20, 610, 760))),
    ]

def snapper(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    bracket = band("M 110 420 V 190 Q 110 110 190 110 H 420", 120)
    return [
        ("bracket", p, 0, svg(bracket)),
        ("pupil", b, 0, svg(circle(640, 640, 190))),
        ("lens", t, 1, svg(circle(640, 640, 430))),
    ]

def switchboard(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    return [
        ("hub", p, 0, svg(circle(360, 512, 120))),
        ("upper", t, 1, svg(band("M -160 512 H 340 C 560 512 620 230 1200 190", 210))),
        ("lower", b, 1, svg(band("M -160 512 H 340 C 560 512 620 794 1200 834", 210))),
    ]

def paper(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    sheet = shape("M 266 130 H 670 L 930 390 V 1160 H 266 Q 170 1160 170 1064 V 226 Q 170 130 266 130 Z")
    fold = shape("M 670 130 L 930 390 H 750 Q 670 390 670 310 Z")
    behind = rrect(60, 230, 700, 1000, 96, -9, 410, 730)
    return [
        ("fold", p, 0, svg(fold)),
        ("sheet", t, 0, svg(sheet)),
        ("behind", b, 2, svg(behind)),
    ]

def tidy(a):
    import math
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    # a broom: handle up to the top right, a ferrule bar across its end, bristles splaying down-left
    fx0, fy0, fx1, fy1 = 560, 230, 830, 500  # ferrule, perpendicular to the handle
    bristles = []
    for i in range(5):
        s = i / 4
        sx, sy = fx0 + (fx1 - fx0) * s, fy0 + (fy1 - fy0) * s
        r = math.radians(150 - 30 * s)  # splay: outer bristles lean out
        bristles.append(band(f"M {sx:.0f} {sy:.0f} L {sx + 560 * math.cos(r):.0f} {sy + 560 * math.sin(r):.0f}", 112))
    return [
        ("handle", p, 0, svg(band("M 700 360 L 1160 -100", 150), band(f"M {fx0} {fy0} L {fx1} {fy1}", 120))),
        ("bristles", t, 0, svg(*bristles)),
        ("sweep", b, 1, svg(band("M -140 760 Q 420 1140 1180 940", 180))),
    ]

def commit(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    return [
        ("stations", p, 0, svg(circle(330, 770, 150), circle(730, 330, 150))),
        ("branch", b, 1, svg(band("M 330 1200 V 700 C 330 470 480 330 730 330 H 1200", 150))),
        ("trunk", t, 1, svg(band("M 330 -160 V 1200", 150))),
    ]

def awake(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    rays = [band("M 512 120 V 250", 110), band("M 210 250 L 290 350", 110), band("M 814 250 L 734 350", 110)]
    return [
        ("rays", p, 0, svg(*rays)),
        ("sun", t, 0, svg(circle(512, 860, 400))),
        ("horizon", b, 1, svg(rrect(-120, 790, 1264, 400, 120))),
    ]

def dropper(a):
    t, b, p = col(a["top"]), col(a["bottom"]), col(a["pop"])
    drop = shape("M 512 40 C 600 210 780 330 780 540 A 268 268 0 0 1 244 540 C 244 330 424 210 512 40 Z")
    return [
        ("drop", t, 0, svg(drop)),
        ("splash", p, 0, svg(circle(512, 920, 90))),
        ("ring", b, 1, svg(ring(512, 1000, 360, 130))),
    ]

COMPOSITIONS = {"Clips": clips, "Snapper": snapper, "Switchboard": switchboard, "Paper": paper,
                "Tidy": tidy, "Commit": commit, "Awake": awake, "Dropper": dropper}


def make(app, a):
    pieces = COMPOSITIONS[app](a)
    groups = [piece(name, hexcol, step) for name, hexcol, step, _ in pieces]
    assets = {name: art for name, _, _, art in pieces}
    return background(a), groups, assets


if __name__ == "__main__":
    kit.build("R2-Geometry", make)
    print(kit.big_sheet("R2-Geometry"))
