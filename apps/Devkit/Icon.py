"""Devkit: the tile is a pegboard. An open-end wrench hangs from the top and runs off the bottom edge, a
screwdriver hangs beside it by its handle hole. Print: sage on the board (ground)."""
from herbarium import *

def parts():
    wx, sx = 320, 736                     # wrench and screwdriver centre lines
    head = cut(disc(wx, 320, 192), rect(wx - 64, 64, 128, 256, 32), "jaw")
    return [
        Part("handle", cut(pill(sx - 96, 128, 192, 448), disc(sx, 224, 32), "hang"), "accent", 0, on="tile"),
        Part("collar", rect(sx - 64, 544, 128, 96, 32), "ink", 0),
        Part("shaft", rect(sx - 32, 576, 64, 352, 16), "base", 1, on="tile"),
        Part("wrench", head + rect(wx - 64, 448, 128, 640, 64), "base", 1, on="tile"),
    ]
SPEC = Spec(
    name="Devkit", tile=TILES["slate"],
    main="#59626B", main2="#A7A9AA", main3="#4C5258", accent=ACCENTS["ochre"], muted="#9AA3AB",
    parts=parts,
    print=Print(plate="Devkit.jpg", crop=(365, 411, 913),
                erase=[(1152, 913, 148, 388), (1164, 833, 68, 91), (1141, 570, 126, 137),
                       (1187, 422, 80, 80), (354, 1221, 103, 114)],
                plant=("Salvia officinalis", "sage")),
)
