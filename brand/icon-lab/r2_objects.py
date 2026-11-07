#!/usr/bin/env python3
"""Round 2, direction "Objects on ice": a quiet frosted tile, and each app is one chunky object in
translucent candy plastic with its own silhouette. Body, inner parts and details sit on separate
glass groups so the inner part shows through the body (the coloured-plastic effect).

    python3 brand/icon-lab/r2_objects.py
"""
import kit
from kit import FLAVOURS, GRAPHITE, mix, solid, gradient, layer, group, svg_doc

WHITE, WHITE_D = "#FFFFFF", "#F1F2F5"


# ---------------------------------------------------------------- tiny svg helpers

def rr(x, y, w, h, r):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/>'

def circ(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'

def ring(cx, cy, r, hole):
    # evenodd donut
    return (f'<path fill-rule="evenodd" d="M{cx - r},{cy}a{r},{r} 0 1,0 {2 * r},0a{r},{r} 0 1,0 {-2 * r},0z'
            f'M{cx - hole},{cy}a{hole},{hole} 0 1,0 {2 * hole},0a{hole},{hole} 0 1,0 {-2 * hole},0z"/>')

def path(d, rounded=0):
    """Filled path; `rounded` > 0 also strokes it in the same colour with round joins (soft corners)."""
    s = f' stroke="#FFFFFF" stroke-width="{rounded}" stroke-linejoin="round" stroke-linecap="round"' if rounded else ""
    return f'<path d="{d}"{s}/>'

def line(x1, y1, x2, y2, w):
    return (f'<path d="M{x1},{y1}L{x2},{y2}" fill="none" stroke="#FFFFFF" stroke-width="{w}" '
            f'stroke-linecap="round"/>')

def art(*shapes, rot=0, dx=0, dy=0):
    t = f' transform="translate({dx} {dy}) rotate({rot} 512 512)"' if (rot or dx or dy) else ""
    return svg_doc(f'<g fill="#FFFFFF"{t}>{"".join(shapes)}</g>')


# ---------------------------------------------------------------- colour + groups

def tile():
    return gradient("#FFFFFF", "#E3E9F0", "#363A42", "#17191D")

def col(name, lift=0.0):
    """(light, dark) pair for a flavour; dark lifts it a touch so it glows on graphite."""
    base = FLAVOURS[name]
    return mix(base, "#FFFFFF", lift), mix(base, "#FFFFFF", lift + 0.12)

def L(name, colour, opacity=None):
    light, dark = colour
    return layer(name, fill=solid(light, dark), opacity=opacity)

def front(*layers, shadow=0.45):
    return group(list(layers), shadow="neutral", shadow_opacity=shadow, translucency=None)

def body(*layers, see=0.7):
    """The candy-plastic shell: translucent so the group behind shows through."""
    return group(list(layers), shadow="layer-color", shadow_opacity=0.7, translucency=see)

def back(*layers):
    return group(list(layers), shadow="none", shadow_opacity=0.0, translucency=None)


# ---------------------------------------------------------------- objects

def clips(a):
    rot = -7
    board = art(rr(222, 176, 580, 744, 84), rot=rot)
    paper = art(rr(290, 290, 444, 560, 40), rot=rot)
    lines = art(rr(356, 420, 312, 50, 25), rr(356, 530, 312, 50, 25), rr(356, 640, 200, 50, 25), rot=rot)
    clip = art('<path fill-rule="evenodd" d="M420,112h184a60,60 0 0 1 60,60v70a50,50 0 0 1 -50,50h-204'
               'a50,50 0 0 1 -50,-50v-70a60,60 0 0 1 60,-60zM462,166h100a24,24 0 0 1 0,48h-100a24,24 0 0 1 0,-48z"/>',
               rot=rot)
    top, pop = col(a["top"]), col(a["pop"])
    groups = [front(L("clip", pop), shadow=0.5),
              front(L("lines", col(a["top"], 0.0)), L("paper", (WHITE, WHITE_D))),
              body(L("board", top), see=0.55)]
    return groups, dict(board=board, paper=paper, lines=lines, clip=clip)

def snapper(a):
    shell = art(rr(112, 330, 800, 520, 120), rr(318, 226, 330, 190, 70), dy=-10)
    ringa = art(ring(512, 590, 214, 128), rr(724, 400, 120, 64, 32), dy=-10)
    core = art(circ(512, 590, 140), dy=-10)
    button = art(rr(162, 262, 130, 110, 40), dy=-10)
    top, pop = col(a["top"]), col(a["pop"])
    groups = [front(L("ring", (WHITE, WHITE_D))),
              body(L("shell", top), see=0.6),
              back(L("core", pop), L("button", pop))]
    return groups, dict(ring=ringa, shell=shell, core=core, button=button)

def switchboard(a):
    # a two-way signpost: one board points right, the other left; the post shows through both
    right = art(path("M170,168H736L866,268L736,368H170Z", rounded=56))
    left = art(path("M854,446H288L158,546L288,646H854Z", rounded=56))
    post = art(rr(468, 120, 88, 790, 44), rr(360, 868, 304, 70, 35))
    top, pop = col(a["top"]), col(a["pop"])
    groups = [body(L("right", top), see=0.75),
              body(L("left", pop), see=0.7),
              back(L("post", (WHITE, WHITE_D)))]
    return groups, dict(right=right, left=left, post=post)

def paper(a):
    sheet = art(path("M226,120H612L790,298V888H226Z", rounded=64), dx=-40)
    fold = art(path("M612,120V298H790Z", rounded=40), dx=-40)
    lines = art(rr(300, 380, 300, 46, 23), rr(300, 480, 380, 46, 23), rr(300, 580, 250, 46, 23), dx=-40)
    # pen, diagonal, breaking past the sheet's right edge
    pen = art(rr(452, 200, 120, 520, 56), path("M452,690L512,840L572,690Z", rounded=30),
              rot=38, dx=210, dy=90)
    nib = art(path("M482,770L512,840L542,770Z", rounded=14), rot=38, dx=210, dy=90)
    top, pop = col(a["top"]), col(a["pop"])
    groups = [front(L("nib", (WHITE, WHITE_D)), L("pen", pop), shadow=0.5),
              front(L("fold", (WHITE, WHITE_D)), L("lines", (WHITE, WHITE_D), opacity=0.9)),
              body(L("sheet", top), see=0.55)]
    return groups, dict(pen=pen, nib=nib, fold=fold, lines=lines, sheet=sheet)

def tidy(a):
    rot = -12
    head = art('<path fill-rule="evenodd" d="M150,330h340v120h-340a60,60 0 0 1 0,-120z'
               'M190,390a28,28 0 1,0 56,0a28,28 0 1,0 -56,0z"/>',
               rr(410, 270, 480, 270, 80), rot=rot, dy=-30)
    band = art(rr(460, 330, 380, 48, 24), rot=rot, dy=-30)
    bristles = art(path("M430,500H870L900,800H400Z", rounded=40), rot=rot, dy=-30)
    grooves = art(*[rr(478 + i * 70, 640, 22, 190, 11) for i in range(6)], rot=rot, dy=-30)
    top, pop = col(a["top"]), col(a["pop"])
    groups = [front(L("band", (WHITE, WHITE_D))),
              body(L("head", top), see=0.55),
              back(L("grooves", (WHITE, WHITE_D), opacity=0.55), L("bristles", pop))]
    return groups, dict(band=band, head=head, bristles=bristles, grooves=grooves)

def commit(a):
    # a chunky Y-shaped connector piece (a pipe junction), with collars at its three ends
    pipe = svg_doc('<path d="M330,860V200M330,600C330,420 470,330 690,300" fill="none" stroke="#FFFFFF" '
                   'stroke-width="150" stroke-linecap="round"/>')
    collars = art(ring(330, 196, 128, 56), ring(700, 300, 128, 56), ring(330, 830, 128, 56))
    cores = art(circ(330, 196, 56), circ(700, 300, 56), circ(330, 830, 56))
    top, pop = col(a["top"]), col(a["pop"])
    groups = [front(L("collars", pop), shadow=0.5),
              body(L("pipe", top), see=0.6),
              back(L("cores", (WHITE, WHITE_D)))]
    return groups, dict(collars=collars, pipe=pipe, cores=cores)

def awake(a):
    mug = art(rr(170, 330, 520, 580, 110), dx=-20)
    handle = art(ring(720, 600, 170, 86), dx=-20)
    coffee = art(rr(222, 540, 416, 320, 64), dx=-20)
    steam = svg_doc('<g fill="none" stroke="#FFFFFF" stroke-width="56" stroke-linecap="round">'
                    '<path d="M310,250C270,210 350,170 310,120"/><path d="M430,250C390,210 470,170 430,120"/>'
                    '<path d="M550,250C510,210 590,170 550,120"/></g>')
    top, pop, bot = col(a["top"]), col(a["pop"]), col(a["bottom"])
    groups = [front(L("steam", (WHITE, WHITE_D)), shadow=0.3),
              body(L("mug", top), see=0.75),
              back(L("coffee", pop), L("handle", bot))]
    return groups, dict(steam=steam, mug=mug, handle=handle, coffee=coffee)

def dropper(a):
    k = dict(rot=42, dy=0)
    bulb = art(rr(392, 20, 240, 330, 120), **k)
    collar = art(rr(340, 320, 344, 100, 50), **k)
    tube = art(path("M424,410H600V780L512,960L424,780Z", rounded=56), **k)
    liquid = art(path("M462,600H562V790L512,900L462,790Z", rounded=28), **k)
    top, pop, bot = col(a["top"]), col(a["pop"]), col(a["bottom"])
    groups = [front(L("collar", (WHITE, WHITE_D)), L("bulb", top)),
              body(L("tube", (mix(FLAVOURS[a["bottom"]], "#FFFFFF", 0.7), mix(FLAVOURS[a["bottom"]], "#FFFFFF", 0.55))),
                   see=0.8),
              back(L("liquid", col(a["bottom"], -0.0)))]
    return groups, dict(bulb=bulb, collar=collar, tube=tube, liquid=liquid)

OBJECTS = dict(Clips=clips, Snapper=snapper, Switchboard=switchboard, Paper=paper, Tidy=tidy,
               Commit=commit, Awake=awake, Dropper=dropper)


def make(app, a):
    groups, assets = OBJECTS[app](a)
    return tile(), groups, assets


if __name__ == "__main__":
    kit.build("R2-Objects", make)
    print(kit.big_sheet("R2-Objects"))
