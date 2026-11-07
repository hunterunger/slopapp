"""Snapper: the tile is a camera front. A grip band, a big lens (rim, barrel, glass, glint), shutter
button on the top edge, flash. Print: mallow on the body (ground)."""
from herbarium import *

def parts():
    cx, cy = 512, 544
    return [
        Part("glint", disc(448, 480, 32), "base", 0, on="ink"),
        Part("glass", disc(cx, cy, 192), "ink", 0, on="main3"),
        Part("rim", ring(cx, cy, 320, 64), "base", 1, on="tile"),
        Part("barrel", disc(cx, cy, 256), "main3", 1),
        Part("shutter", rect(160, -64, 192, 160, 64), "accent", 2, on="tile"),
        Part("flash", pill(672, 128, 192, 96), "base", 2, on="tile"),
        Part("band", rect(-64, 416, 1152, 256), "main3", 2, on="tile"),
    ]

SPEC = Spec(
    name="Snapper", tile=TILES["clay"],
    main="#C4704F", main2="#E5B9A4", main3="#8F4B33", accent=ACCENTS["ochre"], muted="#E8DCC8",
    parts=parts,
    print=Print(plate="Snapper.jpg", crop=(250, 150, 1000), erase=[(1150, 0, 300, 1300)],
                plant=("Malva sylvestris", "common mallow")),
)
