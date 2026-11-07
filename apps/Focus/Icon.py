"""Focus: the tile is an hourglass, front-on. Its top and bottom plates run off the tile, the glass
spans them, and the last of the sand runs through. Print: lavender on the ground."""
from herbarium import *

def parts():
    top = rpoly([(128, 128), (896, 128), (544, 480), (480, 480)], 32)
    bottom = rpoly([(480, 544), (544, 544), (896, 896), (128, 896)], 32)
    glass = top + bottom + rect(480, 448, 64, 128)
    sand = (rpoly([(416, 384), (608, 384), (544, 448), (480, 448)], 16)
            + rpoly([(512, 640), (736, 864), (288, 864)], 32) + stroke("M512,448 L512,672", H))
    return [
        Part("sand", sand, "accent", 0, on="muted"),
        Part("glass", glass, "muted", 1, on="tile"),
        Part("plates", rect(-64, -64, 1152, 192) + rect(-64, 896, 1152, 192), "base", 2, on="tile"),
    ]

SPEC = Spec(
    name="Focus", tile=TILES["dusk"],
    main="#46597A", main2="#9EA4B1", main3="#3F4C62", accent=ACCENTS["clay"], muted="#CDD2DB",
    parts=parts,
    print=Print(plate="Focus.jpg", crop=(300, 420, 880), erase=[(1080, 1200, 100, 100), (1150, 420, 30, 880)],
                plant=("Lavandula angustifolia", "lavender")),
)
