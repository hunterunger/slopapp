"""Awake: a coffee cup from above on a saucer; the tile is the table. Print: coffee on the saucer
(botanical china), cleared around the cup."""
from herbarium import *

def parts():
    cx, cy = 448, 512
    return [
        Part("coffee", disc(cx, cy, 256), "ink", 0, on="base"),
        Part("cup", ring(cx, cy, 320, 64) + pill(704, 448, 256, 128), "base", 1, on="main2"),
        Part("saucer", disc(512, 512, 448), "main2", 2, on="tile"),
    ]

SPEC = Spec(
    name="Awake", tile=TILES["rosewood"],
    main="#C98F86", main2="#D9A79E", main3="#8E5A52", accent=ACCENTS["lingonberry"], muted="#E6D7CF",
    light={"ink": WALNUT}, dark={"ink": "#2E241C"},
    parts=parts,
    print=Print(plate="Awake.jpg", crop=(80, 100, 1200), erase=[(1000, 60, 375, 140), (0, 1050, 280, 500)],
                on="saucer", clear=["cup"],
                plant=("Coffea arabica", "coffee")),
)
