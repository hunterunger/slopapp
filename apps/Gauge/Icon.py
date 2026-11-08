"""Gauge: a dial instrument, face-on. The tile is the instrument's case; the dial face sits low and
runs off the bottom edge, ringed by its bezel. A scale arcs over the top, cut into four by ticks at
45 degrees, and the needle (the part that acts) points up and to the right from the hub.

Print: dandelion on the dial face. A dandelion clock is the gauge children read by blowing on it,
and the plant's jagged leaves print well; cleared around the scale, the needle and the hub."""
from herbarium import *

TILE = TILES["tarn"]
CX, CY = 512, 704          # the hub; the face's centre
FACE = 384                 # face radius inside the bezel
SCALE, SCALE_W = 320, W2   # scale band: outer radius and width (a 64 gap inside the bezel)


def ticks():
    """Radial cuts through the scale at 45, 90 and 135 degrees."""
    k = 0.7071067811865476
    cuts = stroke(f"M{CX},{CY - 192} L{CX},{CY - 416}", H)
    for s in (-1, 1):
        cuts += stroke(f"M{CX + s * 192 * k:.2f},{CY - 192 * k:.2f} L{CX + s * 416 * k:.2f},{CY - 416 * k:.2f}", H)
    return cuts


def parts():
    lower_half = rect(-64, CY, 1152, 512)
    scale = cut(cut(ring(CX, CY, SCALE, SCALE_W), lower_half, "below"), ticks(), "ticks")
    return [
        Part("hub", disc(CX, CY, 64), "ink", 0, on="accent"),
        Part("needle", rot(pill(-32, -32, 352, 64), CX, CY, -45), "accent", 0, on="surface"),
        Part("scale", scale, "main", 1, on="surface"),
        Part("face", disc(CX, CY, FACE), "surface", 2, on="main3"),
        Part("bezel", ring(CX, CY, FACE + 64, 64), "main3", 2, on="tile"),
    ]


SPEC = Spec(
    name="Gauge",
    tile=TILE,
    main=TILE,
    main2=mix(TILE, BIRCH, 0.5),
    main3=mix(TILE, CHAR, 0.3),
    accent=ACCENTS["lingonberry"],
    muted=mix(TILE, BIRCH, 0.7),
    parts=parts,
    print=Print(plate="Gauge.jpg", crop=(130, 330, 1050), on="face", clear=["scale", "needle", "hub"],
                erase=[(1000, 780, 110, 140)],
                plant=("Taraxacum officinale", "dandelion")),
)
