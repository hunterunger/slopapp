"""Ruler: a ruler crosses the tile corner to corner, ticks along its upper edge; a cursor frame slides
on it, framing one tick. Print: anise on the ground."""
from herbarium import *

def parts():
    o = (512, 512)
    body = rect(-896, -160, 1792, 320)
    ticks = "".join(rect(x, -160, 32, 128 if (x // 96) % 2 == 0 else 64, 16) for x in range(-768, 769, 96))
    cursor = cut(rect(-96, -256, 224, 512, 32), rect(-32, -192, 96, 384), "window")   # frames tick 0
    return [
        Part("cursor", rot(cursor, *o, -45), "accent", 0, on="surface"),
        Part("ticks", rot(ticks, *o, -45), "main3", 0, on="surface"),
        Part("ruler", rot(body, *o, -45), "surface", 1, on="tile"),
    ]

SPEC = Spec(
    name="Ruler", tile=TILES["sand"],
    main="#CDB892", main2="#E1D4BD", main3="#9E8E73", accent=ACCENTS["lingonberry"], muted="#E1D4BD",
    parts=parts,
    print=Print(plate="Ruler.jpg", crop=(214, 238, 905), erase=[(95, 905, 155, 250)],
                plant=("Pimpinella anisum", "anise")),
)
