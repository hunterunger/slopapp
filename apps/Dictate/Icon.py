"""Dictate: a broadcast microphone, front-on: the capsule head with its grille cut through, held in a
yoke whose stem runs off the bottom; the live light glows. Print: marshmallow (the throat-soother)
on the ground."""
from herbarium import *

def parts():
    slots = pill(352, 192, 320, 64) + pill(352, 320, 320, 64) + pill(352, 448, 320, 64)
    yoke = stroke("M160,384 L160,512 A352,352 0 0,0 864,512 L864,384", W2) + rect(448, 864, 128, 224)
    return [
        Part("live", disc(512, 640, 64), "accent", 0, on="main"),
        Part("head", cut(pill(256, 64, 512, 704), slots, "grille"), "main", 1, on="tile"),
        Part("yoke", yoke, "base", 2, on="tile"),
    ]

SPEC = Spec(
    name="Dictate", tile=TILES["lichen"],
    main="#6E7252", main2="#CFCFB3", main3="#848765", accent=ACCENTS["ochre"], muted="#C9CCAA",
    parts=parts,
    print=Print(plate="Dictate.jpg", crop=(320, 560, 960),
                erase=[(880, 720, 190, 190), (1070, 560, 230, 380), (1040, 940, 260, 230), (1150, 1330, 130, 150),
                       (1030, 1480, 220, 60), (600, 1430, 50, 50)],
                plant=("Althaea officinalis", "marsh mallow")),
)
