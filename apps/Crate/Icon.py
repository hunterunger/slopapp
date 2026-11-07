"""Crate: the tile is a slatted wooden crate seen from the front, open at the top. Planks run off both
sides with dark gaps between them, corner posts hold them, and files stand up out of it; the one being
lifted out is the accent. Print: cork oak on the ground behind the crate."""
from herbarium import *

def parts():
    planks = rect(-64, 448, 1152, 192) + rect(-64, 704, 1152, 192) + rect(-64, 960, 1152, 128)
    return [
        Part("posts", rect(64, 448, 128, 640, 32) + rect(832, 448, 128, 640, 32), "main3", 0, on="main2"),
        Part("planks", planks, "main2", 1, on="ink"),
        Part("inside", rect(-64, 448, 1152, 640), "ink", 2, on="tile"),
        Part("file", rect(256, 192, 256, 320, 32), "accent", 2, on="tile"),
        Part("files", rect(576, 256, 192, 256, 32), "muted", 2, on="tile"),
    ]

SPEC = Spec(
    name="Crate", tile=TILES["bark"],
    main="#8A847A", main2="#C0BAB1", main3="#66615A", accent=ACCENTS["ochre"], muted="#D5D0C7",
    parts=parts,
    print=Print(plate="Crate.jpg", crop=(250, 100, 1000), erase=[(1150, 120, 290, 90)],
                plant=("Quercus suber", "cork oak")),
)
