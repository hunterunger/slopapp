"""Squish: the tile is a screw press: a frame over a bed that bleeds off the bottom; the platen
presses a sheet thin and wide. Print: pomegranate on the ground."""
from herbarium import *

def parts():
    frame = cut(rect(128, 128, 768, 1024, 128), rect(256, 256, 512, 1024, 0), "window")
    return [
        Part("platen", rect(320, 576, 384, 192, 32), "accent", 0, on="tile"),
        Part("screw", rect(448, 256, 128, 320), "ink", 1),
        Part("sheet", pill(256, 768, 512, 64), "base", 1, on="main3"),
        Part("frame", frame, "main3", 2, on="tile"),
        Part("bed", rect(-64, 832, 1152, 256), "main3", 2, on="tile"),
    ]

SPEC = Spec(
    name="Squish", tile=TILES["cloudberry"],
    main="#DE9F57", main2="#EAC8A0", main3="#AA7D4A", accent=ACCENTS["lingonberry"], muted="#EED8BC",
    parts=parts,
    print=Print(plate="Squish.jpg", crop=(300, 250, 850),
                erase=[(840, 140, 500, 420), (1060, 620, 160, 260), (660, 120, 120, 150), (310, 770, 70, 130)],
                plant=("Punica granatum", "pomegranate")),
)
