"""Commit: a transit map. The main line runs edge to edge, a branch leaves it on an r-256 bend,
stations are rings at the joins. Print: an oak twig on the ground."""
from herbarium import *

def parts():
    x, r = 384, BEND_R
    branch = f"M{x},832 L{x},{448 + r} A{r},{r} 0 0 1 {x + r},448 L1088,448"
    return [
        Part("stations", ring(x, 192, 128, 64) + ring(x, 832, 128, 64) + ring(832, 448, 128, 64), "base", 0, on="tile"),
        Part("branch", stroke(branch, W1), "accent", 1, on="tile"),
        Part("main", stroke(f"M{x},-64 L{x},1088", W1), "muted", 2),
    ]

SPEC = Spec(
    name="Commit", tile=TILES["heather"],
    main="#8C7EA0", main2="#C9BFD6", main3="#5F5274", accent=ACCENTS["ochre"], muted="#C3B8D2",
    parts=parts,
    print=Print(plate="Commit.jpg", crop=(330, 450, 1050), erase=[(1080, 450, 320, 300)],
                plant=("Quercus petraea", "sessile oak")),
)
