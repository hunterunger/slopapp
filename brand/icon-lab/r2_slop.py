#!/usr/bin/env python3
"""Round 2 wildcard: Slop. A glossy candy goo pours over the top edge of every tile and drips
down onto the app's object. Shared: the quiet tile, the goo band + drip generator, the white
"sticker" object treatment. Per app: drip positions/lengths, object placement, and one small
interaction (Commit's nodes are drops, Awake's cup holds the goo, Dropper drips it).

    python3 brand/icon-lab/r2_slop.py
"""
import kit
from kit import FLAVOURS, GRAPHITE, mix, c, solid, gradient, layer, group, svg_doc, lucide_parts

# ---------------------------------------------------------------- goo

def wave_to(x, x2, base, amp):
    """Smooth swell from (x, base) to (x2, base), flat (horizontal) at both ends."""
    m, h = (x + x2) / 2, (x - x2) / 4
    amp = max(-abs(x - x2) * 0.1, min(abs(x - x2) * 0.1, amp))  # short gaps stay nearly flat
    return (f" C{x - h:.1f},{base} {m + h:.1f},{base + amp:.1f} {m:.1f},{base + amp:.1f}"
            f" C{m - h:.1f},{base + amp:.1f} {x2 + h:.1f},{base} {x2:.1f},{base}")

def goo_path(base, drips, wave=26, left=-60, right=1084, top=-60):
    """Band from the top edge down to `base`, with rounded drips hanging from it.
    drips: (cx, bottom_y, width). The band edge waves gently between drips."""
    d = f"M{left},{top} L{right},{top} L{right},{base}"
    x = right
    for i, (cx, bottom, w) in enumerate(sorted(drips, key=lambda t: -t[0])):
        r = w * 0.75                     # fillet where the drip leaves the band
        xr, xl = cx + w / 2, cx - w / 2
        wb = w * 0.74                    # the stem narrows before it swells into the drop
        yb = bottom - w * 0.5            # drop centre
        sign = 1 if i % 2 == 0 else -1
        d += wave_to(x, xr + r, base, wave * sign)
        d += f" Q{xr:.1f},{base} {xr:.1f},{base + r:.1f}"
        d += f" C{xr:.1f},{(base + r + yb) / 2:.1f} {cx + wb / 2:.1f},{(base + r + yb) / 2:.1f} {cx + wb / 2:.1f},{yb:.1f}"
        d += f" A{wb / 2:.1f},{wb / 2:.1f} 0 0 1 {cx - wb / 2:.1f},{yb:.1f}"
        d += f" C{cx - wb / 2:.1f},{(base + r + yb) / 2:.1f} {xl:.1f},{(base + r + yb) / 2:.1f} {xl:.1f},{base + r:.1f}"
        d += f" Q{xl:.1f},{base} {xl - r:.1f},{base}"
        x = xl - r
    d += wave_to(x, left, base, -wave) + " Z"
    return f'<path d="{d}" fill="#FFFFFF"/>'

def goo_svg(base, drips, bulbs=(), extra=""):
    """Every drip swells into a drop at its end; bulbs: extra (cx, cy, r) drops (free or nodes)."""
    bulbs = [(x, b - w * 0.5, w * 0.5) for x, b, w in drips] + list(bulbs)
    b = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFFFFF"/>' for x, y, r in bulbs)
    return svg_doc(goo_path(base, drips) + b + extra)

def goo_fill(a):
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    lt = [c(mix(top, "#FFFFFF", 0.08)), c(bot)]
    dk = [c(mix(top, "#FFFFFF", 0.12)), c(mix(bot, "#FFFFFF", 0.05))]
    return {"fill-specializations": [{"value": {"linear-gradient": lt}},
                                     {"appearance": "dark", "value": {"linear-gradient": dk}}]}

# ---------------------------------------------------------------- object (white sticker + coloured lines)

def grid(box, cx, cy):
    k = box / 24
    return k, cx - box / 2, cy - box / 2

def obj_g(parts, box, cx, cy, inner, stroke, fill="none", colour="#FFFFFF"):
    k, tx, ty = grid(box, cx, cy)
    return (f'<g transform="translate({tx:.1f} {ty:.1f}) scale({k:.4f})" fill="{fill}" stroke="{colour}" '
            f'stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">{"".join(inner)}</g>')

def sticker_svg(parts, filled, box, cx, cy, sw=5.0):
    """Chunky white silhouette: every part stroked wide, closed parts filled."""
    return svg_doc(obj_g(parts, box, cx, cy, parts, sw) +
                   obj_g(parts, box, cx, cy, filled, sw, fill="#FFFFFF"))

def lines_svg(parts, box, cx, cy, sw=2.4):
    return svg_doc(obj_g(parts, box, cx, cy, parts, sw))

def lum(h):
    r, g, b = kit.lab.hx(h)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def deep(a):
    darker = min(FLAVOURS[a["top"]], FLAVOURS[a["bottom"]], key=lum)
    return mix(darker, GRAPHITE, 0.22)

# ---------------------------------------------------------------- per app

def P(app, keep=None):
    parts = lucide_parts(app)
    return parts if keep is None else [parts[i] for i in keep]

SLOP = {
    # base: band edge y; drips: (cx, bottom, width), each ends in a drop; bulbs: extra drops;
    # obj: (box, cx, cy) of the Lucide object; fill: closed parts that get a white body
    "Clips": dict(base=420, drips=[(190, 780, 96), (560, 590, 76), (870, 650, 84)],
                  bulbs=[], obj=(560, 512, 650), fill=[0, 1], front="goo"),
    "Snapper": dict(base=380, drips=[(175, 800, 96), (600, 560, 78), (900, 560, 80)],
                    bulbs=[], obj=(620, 512, 660), fill=None, front="goo"),
    "Switchboard": dict(base=300, drips=[(662, 440, 100), (400, 580, 80), (140, 760, 90), (900, 560, 76)],
                        bulbs=[(362, 775, 66)], obj=(600, 512, 610), fill=[],
                        front="obj"),
    "Paper": dict(base=400, drips=[(320, 600, 80), (880, 790, 96), (120, 560, 76)],
                  bulbs=[], obj=(560, 500, 670), fill=[0, 2], front="goo"),
    "Tidy": dict(base=420, drips=[(512, 580, 84), (180, 800, 96), (860, 660, 84)],
                 bulbs=[], obj=(600, 512, 650), fill=[1, 2], front="goo"),
    "Dropper": dict(base=390, drips=[(440, 620, 80), (910, 740, 92), (130, 540, 76)],
                    bulbs=[(286, 932, 34)], obj=(560, 540, 615), fill=[1], front="goo"),
}

def standard(app, a, s):
    box, cx, cy = s["obj"]
    parts = P(app)
    filled = [p for i, p in enumerate(parts) if i in s["fill"]] if s["fill"] is not None else \
        [p for p in parts if kit.lab.is_closed(p)]
    goo = group([layer("goo", fill=goo_fill(a))], shadow="layer-color", shadow_opacity=0.55,
                translucency=0.06 if s["front"] == "goo" else 0.12)
    ink = deep(a)
    obj = group([layer("lines", fill=solid(ink, ink)),
                 layer("body", fill=solid("#FFFFFF", "#F4F5F7"))],
                shadow="neutral", shadow_opacity=0.45, translucency=None)
    assets = {"goo": goo_svg(s["base"], s["drips"], s["bulbs"]),
              "lines": lines_svg(parts, box, cx, cy), "body": sticker_svg(parts, filled, box, cx, cy)}
    groups = [goo, obj] if s["front"] == "goo" else [obj, goo]
    return groups, assets

def commit(a):
    """The goo is the glyph: the trunk is a long drip ending in a node, the branch a short drip."""
    box, cx, cy = 640, 512, 560
    k, x0, y0 = grid(box, cx, cy)
    X, Y = (lambda v: x0 + v * k), (lambda v: y0 + v * k)
    w, rn = 74, 96
    curve = (f'<path d="M{X(18):.1f},{Y(6):.1f} M{X(15):.1f},{Y(6):.1f} '
             f'A{9 * k:.1f},{9 * k:.1f} 0 0 0 {X(6):.1f},{Y(15):.1f}" fill="none" stroke="#FFFFFF" '
             f'stroke-width="{w}" stroke-linecap="round"/>')
    goo = goo_svg(330, [(X(6), Y(18), w), (X(18), Y(6), w), (890, 560, 80), (120, 500, 70)],
                  [(X(6), Y(18), rn), (X(18), Y(6), rn)], curve)
    dots = svg_doc(f'<circle cx="{X(6):.1f}" cy="{Y(18):.1f}" r="38" fill="#FFFFFF"/>'
                   f'<circle cx="{X(18):.1f}" cy="{Y(6):.1f}" r="38" fill="#FFFFFF"/>')
    groups = [group([layer("dots", fill=solid("#FFFFFF", "#FFFFFF"))], shadow="neutral",
                    shadow_opacity=0.35, translucency=0.1),
              group([layer("goo", fill=goo_fill(a))], shadow="layer-color", shadow_opacity=0.6,
                    translucency=0.15)]
    return groups, {"goo": goo, "dots": dots}

def awake(a):
    """The goo pours into the cup: the cup is outlined, its contents are goo."""
    box, cx, cy = 600, 540, 650
    cup = P("Awake", [2])
    k, x0, y0 = grid(box, cx, cy)
    X, Y = (lambda v: x0 + v * k), (lambda v: y0 + v * k)
    inside = (f'<path d="M{X(3.6):.1f},{Y(8.6):.1f} H{X(16.4):.1f} V{Y(17):.1f} '
              f'A{3.4 * k:.1f},{3.4 * k:.1f} 0 0 1 {X(13):.1f},{Y(20.4):.1f} H{X(7):.1f} '
              f'A{3.4 * k:.1f},{3.4 * k:.1f} 0 0 1 {X(3.6):.1f},{Y(17):.1f} Z" fill="#FFFFFF"/>')
    goo = goo_svg(370, [(X(9.5), Y(9.5), 84), (170, 760, 92), (880, 600, 80)], [], inside)
    ink = deep(a)
    groups = [group([layer("lines", fill=solid(ink, ink)),
                     layer("outline", fill=solid("#FFFFFF", "#F4F5F7"))],
                    shadow="neutral", shadow_opacity=0.5, translucency=None),
              group([layer("goo", fill=goo_fill(a))], shadow="layer-color", shadow_opacity=0.55,
                    translucency=0.1)]
    return groups, {"goo": goo, "lines": lines_svg(cup, box, cx, cy, sw=2.4),
                    "outline": lines_svg(cup, box, cx, cy, sw=5.0)}

def make(app, a):
    bg = gradient("#FFFFFF", "#E8EDF2", "#30343B", "#15171B")
    if app == "Commit":
        groups, assets = commit(a)
    elif app == "Awake":
        groups, assets = awake(a)
    else:
        groups, assets = standard(app, a, SLOP[app])
    return bg, groups, assets

if __name__ == "__main__":
    kit.build("R2-Slop", make)
    print(kit.big_sheet("R2-Slop"))
