"""Tally: the tile is a ledger pad. A bound top, right-aligned figures, a plus, the sum rule and the
total in the accent. Print: black mustard on the sheet, cleared around the figures."""
from herbarium import *

def parts():
    sheet = rect(128, 192, 768, 960, 128)
    return [
        Part("total", pill(448, 768, 320, 128), "accent", 0, on="surface"),
        Part("figures", pill(384, 416, 384, 64) + pill(448, 544, 320, 64), "main2", 1, on="surface"),
        Part("plus", pill(192, 544, 192, 64) + pill(256, 480, 64, 192), "main3", 1, on="surface"),
        Part("rule", rect(192, 672, 576, 32, 16), "main3", 1, on="surface"),
        Part("binding", cut(sheet, rect(0, 320, 1024, 800), "bind"), "main3", 1, on="tile"),
        Part("sheet", sheet, "surface", 2, on="tile"),
    ]

SPEC = Spec(
    name="Tally", tile=TILES["rye"],
    main="#B8955F", main2="#D6C2A3", main3="#8F764F", accent=ACCENTS["lingonberry"], muted="#E6D9C3",
    dark={"surface": "#35322D"},   # the dark rye tile sits too close to the standard dark sheet
    parts=parts,
    print=Print(plate="Tally.jpg", crop=(97, 169, 870), erase=[(109, 604, 205, 435), (665, 810, 157, 242)],
                on="sheet", clear=["total", "figures", "plus", "rule", "binding"],
                plant=("Brassica nigra", "black mustard")),
)
