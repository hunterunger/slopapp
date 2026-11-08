"""Shorthand: the tile is a card with a whole block of text on it; a rubber stamp (the few letters
you type) presses the block down in one go. Print: rosemary (for remembrance) on the card,
cleared around the lines."""
from herbarium import *

TILE = TILES["sloe"]

def parts():
    knob = disc(512, 128, 96)
    neck = rect(448, 160, 128, 160, 32)
    base = rect(320, 288, 384, 96, 32)
    lines = (pill(256, 544, 512, 64) + pill(256, 672, 448, 64) + pill(256, 800, 512, 64)
             + pill(256, 928, 320, 64))
    return [
        Part("stamp", knob + neck + base, "accent", 0, on="tile"),
        Part("lines", lines, "main", 1, on="base"),
        Part("card", rect(128, 416, 768, 736, 128), "base", 2, on="tile"),
    ]

SPEC = Spec(
    name="Shorthand",
    tile=TILE,
    main=TILE,
    main2=mix(TILE, BIRCH, 0.5),
    main3=mix(TILE, CHAR, 0.3),
    accent=ACCENTS["ochre"],
    muted=mix(TILE, BIRCH, 0.7),
    parts=parts,
    print=Print(plate="Shorthand.jpg", crop=(420, 380, 640), on="card", clear=["lines"],
                plant=("Rosmarinus officinalis", "rosemary")),
)
