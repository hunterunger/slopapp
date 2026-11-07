"""Dropper: a paint-chip strip bleeding off top and bottom; a pipette lifts the accent chip.
Print: foxglove on the ground."""
from herbarium import *

def parts():
    body = rpoly([(0, 0), (64, -192), (-64, -192)], 32) + rect(-64, -448, 128, 288, 32)   # tip at origin
    liquid = rpoly([(0, -64), (32, -192), (-32, -192)], 16) + rect(-32, -320, 64, 160, 32)
    bulb, collar, tip = pill(-128, -800, 256, 320), rect(-128, -512, 256, 64, 32), (384, 704)
    return [
        Part("bulb", rot(bulb, *tip, 45), "accent", 0, on="tile"),
        Part("collar", rot(collar, *tip, 45), "ink", 0),
        Part("liquid", rot(liquid, *tip, 45), "accent", 0, on="base"),
        Part("tube", rot(body, *tip, 45), "base", 0, on="tile"),
        Part("chip0", rect(192, 64, 192, 192, 32), "main2", 1, on="surface"),
        Part("chip1", rect(192, 320, 192, 192, 32), "main", 1, on="surface"),
        Part("chip2", rect(192, 576, 192, 192, 32), "accent", 1, on="surface"),
        Part("chip3", rect(192, 832, 192, 192, 32), "main3", 1, on="surface"),
        Part("strip", rect(128, -64, 320, 1152, 64), "surface", 2),
    ]

SPEC = Spec(
    name="Dropper", tile=TILES["blush"],
    main="#C98F86", main2="#E2C2B8", main3="#8E5A52", accent=ACCENTS["spruce"], muted="#F2E7E1",
    parts=parts,
    print=Print(plate="Dropper.jpg", crop=(300, 300, 1100), erase=[(800, 280, 620, 180)],
                plant=("Digitalis purpurea", "foxglove")),
)
