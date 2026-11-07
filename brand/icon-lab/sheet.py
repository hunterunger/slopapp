#!/usr/bin/env python3
"""Builds compare.html: one card per direction (Dock row, dark row, small sizes, clear/tinted, recipe)."""
import os, sys

LAB = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(LAB, "web")
DOCK = ["Clips", "Snapper", "Switchboard", "Paper", "Tidy", "Commit", "Awake", "Dropper"]
LIST = ["Clips", "Snapper", "Switchboard", "Paper", "Tidy", "Commit"]

DIRS = [
    ("A-CandyGlass", "A · Candy Glass",
     "The launcher's sibling. Each app gets its own two-flavour candy gradient; the glyph is frosted white glass with a solid body.",
     "Tile: per-app gradient. Glyph: Lucide lines in white glass + a 40% white body under its closed shapes. One glass group.",
     "Safest and most scriptable. Can look like a lot of other gradient icons; the glyph is the only per-app drawing."),
    ("B-IceJelly", "B · Ice Jelly",
     "Inverted: a frosted ice tile, and the glyph is coloured candy glass, like translucent plastic over white. Dark turns the tile graphite and the glyph glows.",
     "Tile: ice white (graphite in dark). Glyph: lines in the app flavour + a 30% tinted body, coloured shadow. One group.",
     "Calm and very Apple-current. White tiles blend together in a Dock; Clear mode needs a white-glyph override."),
    ("C-TwoFlavour", "C · Two Flavour",
     "Candy tile; the glyph splits in two: the body in white glass, the part that does the work (lens, clip, nodes, brush) in a second flavour, lifted on its own layer.",
     "Tile: per-app gradient. Glyph: two glass groups. Per app: pick the accent parts (indices into the Lucide SVG) and a pop flavour.",
     "Most character and real depth. Needs one small choice per app (which parts pop); some glyphs have no obvious accent."),
    ("E-Bezel", "D · Face Plate",
     "A nod to the reference: a translucent candy shell with a frosted white face plate on top, and a coloured chin peeking out below. Glyph in candy on the plate.",
     "Tile: per-app gradient. Group 1: white plate (graphite in dark). Group 2: candy glyph on the plate, offset up.",
     "The strongest family signature. The plate costs glyph size, so 16 px is harder; the chin needs to stay generous."),
    ("F-Gumdrop", "E · Gumdrop",
     "A shared object: every icon is a glossy candy gumdrop sitting on ice, with a white glyph inside. The family is the gumdrop; the colour and glyph tell them apart.",
     "Tile: ice (graphite in dark). Group 1: white glyph. Group 2: candy disc with the app gradient and a coloured shadow.",
     "Instantly a family, easy to generate. Circle-in-square reads a bit like a button or a badge; glyph is smaller."),
    ("G-Poster", "F · Poster",
     "Oversized glyph, cropped by the tile edge, like a poster or a sticker sheet. Bold and playful; feels less like a template.",
     "As Candy Glass, but the glyph is about 2x and offset so it bleeds off a corner. Per app: crop offset.",
     "Loudest and most fun. Crops hurt recognition for some glyphs (Switchboard, Commit), and 16 px loses the shape."),
]

def img(path, size, cls=""):
    return f'<img src="{os.path.join(WEB, path)}">'

def card(key, title, pitch, recipe, risk):
    dock = "".join(img(f"{key}/{a}-Default.webp", 52) for a in DOCK)
    dark = "".join(img(f"{key}/{a}-Dark.webp", 52) for a in DOCK)
    finder = "".join(
        f'<div class="frow">{img(f"{key}/{a}-Default-16pt.webp", 16)}<span>{a}.app</span></div>' for a in LIST[:4])
    finder_d = "".join(
        f'<div class="frow">{img(f"{key}/{a}-Dark-16pt.webp", 16)}<span>{a}.app</span></div>' for a in LIST[:4])
    p32 = "".join(img(f"{key}/{a}-Default-32pt.webp", 32) for a in LIST)
    modes = "".join(f'<figure>{img(f"{key}/Snapper-{r}.webp", 44)}<figcaption>{l}</figcaption></figure>'
                    for r, l in [("ClearLight", "Clear"), ("ClearDark", "Clear dark"),
                                 ("TintedLight", "Tinted"), ("TintedDark", "Tinted dark")])
    return f"""
<section class="card">
  <header><h2>{title}</h2><p>{pitch}</p></header>
  <div class="wall"><div class="dock">{dock}</div></div>
  <div class="darkrow">{dark}</div>
  <div class="small">
    <div class="finder light"><div class="fh">16 pt list</div>{finder}</div>
    <div class="finder darkf"><div class="fh">16 pt, dark</div>{finder_d}</div>
    <div class="p32"><div class="fh">32 pt</div><div class="p32row">{p32}</div>
      <div class="fh" style="margin-top:10px">Snapper in clear and tinted</div><div class="modes">{modes}</div></div>
  </div>
  <dl><dt>Recipe</dt><dd>{recipe}</dd><dt>Risk</dt><dd>{risk}</dd></dl>
</section>"""

def page(which):
    today = "".join(img(f"Today/{a}-Default.webp", 40) for a in DOCK if os.path.exists(os.path.join(WEB, f"Today/{a}-Default.webp")))
    cards = "".join(card(*d) for d in DIRS if d[0] in which)
    intro = f"""<div class="today"><span>Today</span><div>{today}</div>
<p>Same forest tile and thin cream line for every app: a family, but no colour or depth to tell them apart.</p></div>""" if "A-CandyGlass" in which else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
:root {{ color-scheme: light dark; }}
body {{ margin:0; font-family: var(--font-sans, -apple-system, system-ui); color: var(--foreground); }}
.today {{ display:grid; grid-template-columns:auto auto 1fr; gap:12px; align-items:center; margin:0 0 14px;
  padding:10px 16px; border:1px solid var(--border); border-radius: var(--radius, 10px); }}
.today span {{ font-size:12px; font-weight:600; color: var(--muted-foreground); text-transform:uppercase; letter-spacing:.04em; }}
.today div {{ display:flex; gap:6px; }} .today img {{ width:40px; height:40px; }}
.dock img, .darkrow img {{ width:52px; height:52px; }} .frow img {{ width:16px; height:16px; }} .p32row img {{ width:32px; height:32px; }} .modes img {{ width:44px; height:44px; }}
.today p {{ margin:0; font-size:12.5px; color: var(--muted-foreground); }}
.card {{ border:1px solid var(--border); border-radius: calc(var(--radius, 10px) + 6px); padding:16px; margin:0 0 16px;
  background: var(--card); }}
header h2 {{ margin:0 0 4px; font-size:17px; }}
header p {{ margin:0 0 12px; font-size:13.5px; line-height:1.45; color: var(--muted-foreground); }}
.wall {{ border-radius: var(--radius, 10px); padding:26px 12px 10px; display:flex; justify-content:center;
  background: radial-gradient(120% 140% at 10% 0%, #ffd9e6 0%, #d9ecff 45%, #e8f7e4 100%); }}
.dock {{ display:flex; gap:8px; padding:7px 9px; border-radius:20px; background:rgba(255,255,255,.45);
  border:1px solid rgba(255,255,255,.7); box-shadow:0 8px 24px rgba(30,40,60,.18); backdrop-filter: blur(8px); flex-wrap:wrap; justify-content:center; }}
.darkrow {{ margin-top:8px; border-radius: var(--radius, 10px); padding:12px; display:flex; gap:8px; justify-content:center;
  background: radial-gradient(120% 140% at 90% 0%, #2b2140 0%, #15171b 60%); flex-wrap:wrap; }}
.small {{ display:grid; grid-template-columns: 1fr 1fr 1.6fr; gap:8px; margin-top:8px; }}
.finder {{ border-radius: var(--radius, 10px); padding:8px 10px; font-size:12px; }}
.finder.light {{ background:#fbfbfc; color:#1c1f24; border:1px solid #e3e5e9; }}
.finder.darkf {{ background:#1f2125; color:#e8e9ec; border:1px solid #33363b; }}
.frow {{ display:flex; align-items:center; gap:6px; height:20px; }}
.fh {{ font-size:10.5px; font-weight:600; opacity:.6; text-transform:uppercase; letter-spacing:.04em; margin-bottom:4px; }}
.p32 {{ border-radius: var(--radius, 10px); padding:8px 10px; border:1px solid var(--border); }}
.p32row, .modes {{ display:flex; gap:6px; flex-wrap:wrap; }}
.modes {{ background:#5d6f86; border-radius:8px; padding:6px; }}
figure {{ margin:0; text-align:center; }}
figcaption {{ font-size:9.5px; color:#fff; opacity:.85; }}
dl {{ display:grid; grid-template-columns:auto 1fr; gap:4px 12px; margin:12px 0 0; font-size:12.5px; line-height:1.45; }}
dt {{ font-weight:600; }} dd {{ margin:0; color: var(--muted-foreground); }}
@media (max-width: 560px) {{ .small {{ grid-template-columns:1fr 1fr; }} .p32 {{ grid-column: 1 / -1; }} }}
</style></head><body>{intro}{cards}</body></html>"""

if __name__ == "__main__":
    groups = {"1": ["A-CandyGlass", "B-IceJelly", "C-TwoFlavour"], "2": ["E-Bezel", "F-Gumdrop", "G-Poster"],
              "all": [d[0] for d in DIRS]}
    for k, v in groups.items():
        open(os.path.join(LAB, f"compare-{k}.html"), "w").write(page(v))
    print("ok")
