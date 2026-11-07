#!/usr/bin/env python3
"""Icon lab: builds Icon Composer .icon documents from a Lucide glyph + a recipe, and renders them.

    python3 brand/icon-lab/lab.py [direction ...]     # default: all directions

Writes docs/<Direction>/<App>.icon and renders/<Direction>/<App>-<Rendition>.png (+ small sizes).
Scratch tooling for choosing a style; not part of the pipeline.
"""
import json, os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

LAB = os.path.dirname(os.path.abspath(__file__))
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDITIONS = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]

# ---------------------------------------------------------------- colour

def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

def mix(a, b, t):
    a, b = hx(a), hx(b)
    return "#" + "".join(f"{round((x + (y - x) * t) * 255):02X}" for x, y in zip(a, b))

def c(h, alpha=1.0):
    r, g, b = hx(h)
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"

FLAVOURS = {
    "strawberry": "#F0407A", "tangerine": "#F28A0C", "lemon": "#F2B705", "lime": "#6CCB2F",
    "mint": "#1FBF8F", "lagoon": "#0A9DBF", "blueberry": "#2F6FE4", "grape": "#8A4BD1",
    "bubblegum": "#E255C0", "cherry": "#E23B3B",
}
GRAPHITE, ICE = "#1C1F24", "#F3F6F9"

# Each app: glyph + a two-flavour gradient (top, bottom) + which glyph parts are the "accent".
APPS = {
    # accent = glyph parts (by index) in the second flavour ("pop"); fill = parts that get a solid body
    "Clips":       dict(top="tangerine", bottom="lemon",      pop="strawberry", accent=[0], fill=[0, 1]),
    "Snapper":     dict(top="bubblegum", bottom="strawberry", pop="lemon",      accent=[1]),
    "Switchboard": dict(top="blueberry", bottom="lagoon",     pop="lemon",      accent=[0, 2]),
    "Paper":       dict(top="lagoon",    bottom="mint",       pop="tangerine",  accent=[0], fill=[0, 2]),
    "Tidy":        dict(top="lime",      bottom="mint",       pop="lemon",      accent=[1], fill=[1, 2]),
    "Commit":      dict(top="grape",     bottom="blueberry",  pop="tangerine",  accent=[1, 2]),
    "Awake":       dict(top="cherry",    bottom="tangerine",  pop="lemon",      accent=[0, 1, 3], fill=[2]),
    "Dropper":     dict(top="grape",     bottom="bubblegum",  pop="lemon",      accent=[1], fill=[1]),
}

# ---------------------------------------------------------------- svg

def lucide_parts(app):
    src = open(os.path.join(LAB, "glyphs", f"{app}.svg")).read()
    return re.findall(r"<(?:path|circle|rect|line|polyline|polygon|ellipse)\b[^>]*/>", src)

def is_closed(part):
    if not part.startswith("<path"):
        return True
    d = re.search(r'd="([^"]*)"', part).group(1).strip()
    return d.endswith(("z", "Z"))

def fill_parts(parts, override=None):
    if override is not None:
        return [p for i, p in enumerate(parts) if i in override]
    return [p for p in parts if is_closed(p)]

def solid_svg(parts, colour="#FFFFFF", box=540, stroke=2.25, cx=512, cy=512):
    """Filled silhouette of the given parts (fill + stroke so it reaches the line's outer edge)."""
    return glyph_svg(parts, colour, box, stroke, cx, cy, fill=colour)

def svg_doc(body, size=1024):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{body}</svg>')

def glyph_svg(parts, colour="#FFFFFF", box=540, stroke=2.0, cx=512, cy=512, fill="none"):
    k = box / 24
    tx, ty = cx - box / 2, cy - box / 2
    g = "".join(parts)
    return svg_doc(f'<g transform="translate({tx:.2f} {ty:.2f}) scale({k:.4f})" fill="{fill}" '
                   f'stroke="{colour}" stroke-width="{stroke}" stroke-linecap="round" '
                   f'stroke-linejoin="round">{g}</g>')

def rect_svg(x, y, w, h, r, colour="#FFFFFF"):
    return svg_doc(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{colour}"/>')

def circle_svg(cx, cy, r, colour="#FFFFFF"):
    return svg_doc(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{colour}"/>')

# ---------------------------------------------------------------- icon.json helpers

def solid(light, dark=None, la=1.0, da=None):
    spec = [{"value": {"solid": c(light, la)}}]
    if dark:
        spec.append({"appearance": "dark", "value": {"solid": c(dark, la if da is None else da)}})
    return {"fill-specializations": spec}

def gradient(top, bottom, dtop=None, dbottom=None):
    spec = [{"value": {"linear-gradient": [c(top), c(bottom)]}}]
    if dtop:
        spec.append({"appearance": "dark", "value": {"linear-gradient": [c(dtop), c(dbottom)]}})
    return {"fill-specializations": spec}

def layer(name, glass=True, opacity=None, fill=None, scale=1.0, dy=0):
    d = {"name": name, "image-name": f"{name}.svg", "glass": glass,
         "position": {"scale": scale, "translation-in-points": [0, dy]}}
    if opacity is not None:
        d["opacity"] = opacity
    if fill:
        d.update(fill)
    return d

def group(layers, shadow="neutral", shadow_opacity=0.5, translucency=None, specular=True,
          blur=None, lighting=None, dy=0):
    g = {"layers": layers, "shadow": {"kind": shadow, "opacity": shadow_opacity},
         "specular": specular}
    if translucency is not None:
        g["translucency"] = {"enabled": True, "value": translucency}
    else:
        g["translucency"] = {"enabled": False, "value": 0.5}
    if blur is not None:
        g["blur-material"] = blur
    if lighting:
        g["lighting"] = lighting
    if dy:
        g["position"] = {"scale": 1, "translation-in-points": [0, dy]}
    return g

def write_doc(path, background, groups, assets):
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(os.path.join(path, "Assets"))
    for name, svg in assets.items():
        open(os.path.join(path, "Assets", f"{name}.svg"), "w").write(svg)
    doc = dict(background)
    doc["groups"] = groups  # first group is frontmost
    doc["supported-platforms"] = {"squares": "shared"}
    json.dump(doc, open(os.path.join(path, "icon.json"), "w"), indent=2)

# ---------------------------------------------------------------- directions
# Each returns (background, groups, assets) for one app. groups[0] is frontmost.

def tile_gradient(a):
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    # Dark: graphite with a hint of the flavour (mixing the candy toward black goes muddy).
    return top, bot, gradient(mix(top, "#FFFFFF", 0.08), bot,
                              mix("#30343B", top, 0.22), mix("#121417", bot, 0.12))

def candy_glass(app, a):
    """A: launcher sibling. Candy gradient tile; glyph is frosted white glass with a solid body."""
    top, bot, bg = tile_gradient(a)
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    groups = [group([layer("lines", fill=solid("#FFFFFF", mix(top, "#FFFFFF", 0.35))),
                     layer("body", opacity=0.42, fill=solid("#FFFFFF", mix(top, "#FFFFFF", 0.2)))],
                    shadow="neutral", shadow_opacity=0.5, translucency=0.2)]
    return bg, groups, {"lines": glyph_svg(parts, stroke=2.4), "body": solid_svg(body)}

def ice_jelly(app, a):
    """B: inverted. Frosted ice tile; glyph is coloured candy glass (jelly), body tinted."""
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    bg = gradient("#FFFFFF", "#E6EBF1", "#30343B", "#17191D")
    lit = mix(top, "#FFFFFF", 0.12)
    groups = [group([layer("lines", fill=solid(top, lit)),
                     layer("body", opacity=0.30, fill=solid(bot, bot))],
                    shadow="layer-color", shadow_opacity=0.55, translucency=0.25)]
    return bg, groups, {"lines": glyph_svg(parts, stroke=2.5), "body": solid_svg(body)}

def two_flavour(app, a):
    """C: candy tile; glyph split into two glass groups: body in white, the 'action' part in a
    pale second flavour, lifted for depth."""
    top, bot, bg = tile_gradient(a)
    parts = lucide_parts(app)
    acc = [p for i, p in enumerate(parts) if i in a["accent"]]
    rest = [p for i, p in enumerate(parts) if i not in a["accent"]]
    ac = FLAVOURS[a["pop"]]
    groups = [
        group([layer("accent", fill=solid(ac, ac)),
               layer("accentbody", opacity=0.5, fill=solid(ac, ac))],
              shadow="layer-color", shadow_opacity=0.8, translucency=0.1),
        group([layer("rest", fill=solid("#FFFFFF", "#F2F2F5")),
               layer("restbody", opacity=0.35, fill=solid("#FFFFFF", "#FFFFFF"))],
              shadow="neutral", shadow_opacity=0.45, translucency=0.25),
    ]
    return bg, groups, {"accent": glyph_svg(acc, stroke=2.6),
                        "accentbody": solid_svg(fill_parts(acc, None)),
                        "rest": glyph_svg(rest, stroke=2.6),
                        "restbody": solid_svg(fill_parts(rest, a.get("fill")))}

def graphite_glow(app, a):
    """D: calm and pro. Graphite tile; glyph is luminous candy glass."""
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    bg = gradient("#3B4049", "#1C1F24", "#2A2E35", "#101215")
    lit = mix(top, "#FFFFFF", 0.18)
    groups = [group([layer("lines", fill=solid(lit, lit)),
                     layer("body", opacity=0.38, fill=solid(top, top))],
                    shadow="layer-color", shadow_opacity=1.0, translucency=0.15)]
    return bg, groups, {"lines": glyph_svg(parts, stroke=2.4), "body": solid_svg(body)}

def bezel(app, a):
    """E: iMac nod. Translucent candy shell with a frosted white face plate; glyph in candy
    on the plate; the shell shows below it like the coloured chin."""
    top, bot, bg = tile_gradient(a)
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    plate = rect_svg(88, 80, 848, 700, 190)
    groups = [
        group([layer("lines", fill=solid(top, mix(top, "#FFFFFF", 0.15))),
               layer("body", opacity=0.22, fill=solid(top, top))],
              shadow="layer-color", shadow_opacity=0.4, translucency=None),
        group([layer("plate", fill=solid("#FFFFFF", "#3A3F48"))],
              shadow="neutral", shadow_opacity=0.55, translucency=0.12),
    ]
    return bg, groups, {"lines": glyph_svg(parts, box=520, stroke=2.5, cy=430),
                        "body": solid_svg(body, box=520, cy=430), "plate": plate}

def gumdrop(app, a):
    """F: shared base object. Ice tile with a glossy candy gumdrop carrying a white glyph."""
    top, bot = FLAVOURS[a["top"]], FLAVOURS[a["bottom"]]
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    bg = gradient("#FFFFFF", "#E6EBF1", "#30343B", "#17191D")
    disc = svg_doc('<rect x="152" y="152" width="720" height="720" rx="360" fill="#FFFFFF"/>')
    grad = {"fill-specializations": [{"value": {"linear-gradient": [c(mix(top, "#FFFFFF", 0.1)), c(bot)]}}]}
    groups = [
        group([layer("lines", fill=solid("#FFFFFF", "#FFFFFF")),
               layer("body", opacity=0.35, fill=solid("#FFFFFF", "#FFFFFF"))],
              shadow="neutral", shadow_opacity=0.4, translucency=0.15),
        group([layer("disc", fill=grad)], shadow="layer-color", shadow_opacity=0.7, translucency=0.08),
    ]
    return bg, groups, {"lines": glyph_svg(parts, box=400, stroke=2.6),
                        "body": solid_svg(body, box=400), "disc": disc}

def poster(app, a):
    """G: oversized glyph, cropped by the tile; solid glass shapes, poster-like."""
    top, bot, bg = tile_gradient(a)
    parts = lucide_parts(app)
    body = fill_parts(parts, a.get("fill"))
    dx, dy = a.get("crop", (170, 190))
    groups = [group([layer("lines", fill=solid("#FFFFFF", mix(top, "#FFFFFF", 0.35))),
                     layer("body", opacity=0.3, fill=solid("#FFFFFF", mix(top, "#FFFFFF", 0.2)))],
                    shadow="neutral", shadow_opacity=0.5, translucency=0.2)]
    k = dict(box=1100, cx=512 + dx, cy=512 + dy)
    return bg, groups, {"lines": glyph_svg(parts, stroke=2.2, **k), "body": solid_svg(body, **k)}

DIRECTIONS = {
    "A-CandyGlass": candy_glass,
    "B-IceJelly": ice_jelly,
    "C-TwoFlavour": two_flavour,
    "D-GraphiteGlow": graphite_glow,
    "E-Bezel": bezel,
    "F-Gumdrop": gumdrop,
    "G-Poster": poster,
}

# ---------------------------------------------------------------- render

def render(doc, out, rendition, px, scale=2):
    pts = px // scale
    r = subprocess.run([ICTOOL, doc, "--export-image", "--output-file", out, "--platform", "macOS",
                        "--rendition", rendition, "--width", str(pts), "--height", str(pts),
                        "--scale", str(scale)], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        print("ictool failed", doc, rendition, r.stdout, r.stderr, file=sys.stderr)

def build(direction):
    fn = DIRECTIONS[direction]
    jobs = []
    for app, a in APPS.items():
        doc = os.path.join(LAB, "docs", direction, f"{app}.icon")
        write_doc(doc, *fn(app, a))
        rdir = os.path.join(LAB, "renders", direction)
        os.makedirs(rdir, exist_ok=True)
        for rend in RENDITIONS:
            jobs.append((doc, os.path.join(rdir, f"{app}-{rend}.png"), rend, 512, 2))
        for px in (16, 32, 64):
            for rend in ("Default", "Dark"):
                jobs.append((doc, os.path.join(rdir, f"{app}-{rend}-{px}.png"), rend, px, 1))
    return jobs

if __name__ == "__main__":
    names = sys.argv[1:] or list(DIRECTIONS)
    names = [n for d in names for n in DIRECTIONS if n.startswith(d)]
    jobs = [j for n in names for j in build(n)]
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda j: render(*j), jobs))
    print(f"rendered {len(jobs)} images for {', '.join(names)}")
