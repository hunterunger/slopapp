"""Iconsmith: the tile is the smithy wall; an anvil stands on the bottom edge with a hot icon blank on
its steel face. Print: a rose on the ground."""
from herbarium import *

def parts():
    horn = rpoly([(128, 576), (320, 576), (320, 768)], 32)
    anvil = horn + rect(288, 576, 640, 192, 32) + rect(448, 736, 320, 192) + rect(320, 896, 576, 192, 32)
    return [
        Part("blank", rect(448, 256, 320, 320, 96), "accent", 0, on="tile"),
        Part("face", rect(288, 576, 640, 64, 32), "muted", 1, on="ink"),
        Part("anvil", anvil, "ink", 1, on="tile"),
    ]

SPEC = Spec(
    name="Iconsmith", tile=TILES["lingonberry"],
    main="#A8443A", main2="#CE9A91", main3="#843D35", accent=ACCENTS["ochre"], muted="#DEBCB4",
    parts=parts,
    print=Print(plate="Iconsmith.jpg", crop=(100, 100, 1100),
                erase=[(90, 100, 110, 800), (220, 200, 100, 80), (940, 560, 260, 520)],
                plant=("Rosa × centifolia", "cabbage rose")),
)
