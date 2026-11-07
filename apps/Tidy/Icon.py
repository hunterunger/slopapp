"""Tidy: a broom from above the tile: handle from the top edge, a ferrule, a bristle block fanning off
the bottom with slits that meet at one vanishing point. Print: male fern in the bristles."""
from herbarium import *

VX, VY = 512, -424        # vanishing point of the block's sides
SLITS = (320, 448, 576, 704)

def slit_lines(colour="#FFF"):
    return "".join(f'<path d="M{VX},{VY} L{x + (x - VX) * (1088 - 416) / (416 - VY):.1f},1088" '
                   f'stroke="{colour}" stroke-width="{H}"/>' for x in SLITS)

def parts():
    block = rpoly([(192, 416), (832, 416), (1088, 1088), (-64, 1088)], 32)
    return [
        Part("handle", rect(448, -64, 128, 384, 64), "accent", 0, on="tile"),
        Part("ferrule", rect(192, 288, 640, 128, 64), "base", 0, on="tile"),
        Part("bristles", cut(block, slit_lines() + rect(-64, 352, 1152, 128), "slits"), "main2", 1, on="tile"),
    ]

SPEC = Spec(
    name="Tidy", tile=TILES["pine"],
    main="#3F5E4E", main2="#D8A84E", main3="#2A4236", accent=ACCENTS["clay"], muted="#7E978A",
    parts=parts,
    print=Print(plate="Tidy.jpg", crop=(100, 40, 1150), erase=[(900, 0, 574, 240)], on="bristles",
                mask=rpoly([(192, 480), (832, 480), (1088, 1088), (-64, 1088)], 32) + slit_lines("#000"),
                plant=("Dryopteris filix-mas", "male fern")),
)
