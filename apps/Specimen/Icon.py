"""Specimen: the tile is the face of a type block. A bold single-storey a stands on its baseline,
the x-height and baseline guides run off both edges. Print: hollyhock on the face (ground)."""
from herbarium import *

def parts():
    cx, cy, r = 512, 576, 256
    return [
        Part("letter", ring(cx, cy, r, W1) + rect(cx + r - W1, cy - r, W1, 2 * r, 32), "accent", 0, on="tile"),
        Part("guides", rect(-64, cy - r - 16 - 16, 1152, 32) + rect(-64, cy + r, 1152, 32), "muted", 1, on="tile"),
    ]

SPEC = Spec(
    name="Specimen", tile=TILES["juniper"],
    main="#2F4F57", main2="#92A0A0", main3="#2F454A", accent=ACCENTS["ochre"], muted="#6F8A8E",
    parts=parts,
    # flipped so the flower's centre hides under the stem, not in the counter
    print=Print(plate="Specimen.jpg", crop=(313, 507, 943), flip=True,
                erase=[(306, 436, 141, 295), (1072, 483, 189, 153), (1108, 695, 153, 354),
                       (1214, 1061, 47, 106), (1214, 1273, 47, 177)],
                plant=("Alcea rosea", "hollyhock")),
)
