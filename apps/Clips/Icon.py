"""Clips: the tile is a clipboard. A sheet bleeds off the bottom, the clip bites the top edge, three
clipped cards (the newest in colour). Print: peppermint on the sheet, cleared around the cards."""
from herbarium import *

def parts():
    return [
        Part("clip", cut(rect(320, -128, 384, 384, 128), pill(416, 96, 192, 64), "slot"), "accent", 0, on="tile"),
        Part("card1", pill(256, 352, 512, 128), "main", 1, on="surface"),
        Part("cards", pill(256, 544, 512, 128) + pill(256, 736, 512, 128), "muted", 1, on="surface"),
        Part("sheet", rect(128, 192, 768, 960, 128), "surface", 2, on="tile"),
    ]

SPEC = Spec(
    name="Clips", tile=TILES["ochre"],
    main="#B9473B", main2="#E9D2A6", main3="#8E6A2C", accent=ACCENTS["lingonberry"], muted="#E2C58E",
    dark={"main": "#B9473B"},
    parts=parts,
    print=Print(plate="Clips.jpg", crop=(260, 470, 940), erase=[(1080, 400, 320, 520)],
                on="sheet", clear=["card1", "cards"],
                plant=("Mentha × piperita", "peppermint")),
)
