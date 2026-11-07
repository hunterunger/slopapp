"""Convert: the tile is the face of a tape deck. Two reels on the diagonal: the old format unwinds
from one (ink) and winds onto the other in the accent. Print: cocoa on the deck (ground)."""
from herbarium import *

A, B, R = (320, 320), (704, 704), 128     # reel centres on the 45-degree diagonal, tape pack radius
K = R * math.sqrt(0.5)                    # tangent offset for the strand between the packs

def parts():
    strand = f"M{A[0] - K:.1f},{A[1] + K:.1f} L{B[0] - K:.1f},{B[1] + K:.1f}"
    return [
        Part("hubs", disc(*A, 64) + disc(*B, 64), "base", 0, on="ink"),
        Part("flanges", ring(*A, 192, 32) + ring(*B, 192, 32), "base", 0, on="tile"),
        Part("new", disc(*B, R), "accent", 1, on="tile"),
        Part("old", disc(*A, R), "ink", 1, on="tile"),
        Part("tape", stroke(strand, H), "ink", 2, on="tile"),
    ]

SPEC = Spec(
    name="Convert", tile=TILES["rust"],
    main="#9A5A36", main2="#C8A58F", main3="#6F4831", accent=ACCENTS["ochre"], muted="#DAC3B3",
    parts=parts,
    print=Print(plate="Convert.jpg", crop=(300, 180, 900),
                erase=[(1000, 140, 400, 330), (1140, 470, 60, 190), (1185, 540, 40, 450), (290, 980, 170, 110), (330, 820, 60, 60),
                       (950, 280, 70, 70), (1030, 462, 110, 40)],
                plant=("Theobroma cacao", "cacao")),
)
