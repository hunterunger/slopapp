"""Paper: the tile is a sheet with a dog-eared corner; a pen writes the end of the last line.
Print: flax (linen paper) on the sheet, cleared around the lines."""
from herbarium import *

def parts():
    sheet = rpoly([(-64, 128), (640, 128), (896, 384), (896, 1088), (-64, 1088)], 32)
    flap = rpoly([(640, 128), (896, 384), (640, 384)], 32)
    lines = pill(128, 256, 320, 64) + pill(128, 384, 512, 64) + pill(128, 512, 576, 64) + pill(128, 640, 384, 64)
    pen = rpoly([(0, 0), (64, 192), (-64, 192)], 32) + rect(-64, 192, 128, 832, 32)  # tip at origin
    nib = rpoly([(0, 0), (32, 96), (-32, 96)], 16)
    return [
        Part("nib", rot(nib, 576, 672, -45), "ink", 0, on="accent"),
        Part("pen", rot(pen, 576, 672, -45), "accent", 0, on="surface"),
        Part("lines", lines, "main2", 1, on="surface"),
        Part("flap", flap, "muted", 1),
        Part("sheet", sheet, "surface", 2, on="tile"),
    ]

SPEC = Spec(
    name="Paper", tile=TILES["sage"],
    main="#8EA58B", main2="#B3C1AE", main3="#5D7459", accent=ACCENTS["clay"], muted="#DDE3D6",
    parts=parts,
    print=Print(plate="Paper.jpg", crop=(450, 60, 950), on="sheet", clear=["lines"],
                plant=("Linum usitatissimum", "flax")),
)
