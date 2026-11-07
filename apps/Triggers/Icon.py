"""Triggers: the tile is a laptop's palm rest. The keyboard's bottom row peeks in at the top, the
trackpad runs off the bottom edge, and three fingertips swipe up it (the part that acts), each leaving a short trail. Print:
monkshood, whose deeply divided leaves spread like fingers, on the trackpad, cleared around the
fingertips and their trails."""
from herbarium import *

TILE = TILES["bilberry"]

def parts():
    keys = rect(64, -64, 128, 192, 32) + rect(256, -64, 512, 192, 32) + rect(832, -64, 128, 192, 32)
    tips = disc(320, 576, 64) + disc(512, 512, 64) + disc(704, 576, 64)
    # The swipe: a short trail behind each fingertip, a cut away from it.
    trails = pill(288, 672, 64, 160) + pill(480, 608, 64, 160) + pill(672, 672, 64, 160)
    return [
        Part("fingertips", tips, "accent", 0, on="base"),
        Part("trails", trails, "main2", 1, on="base"),
        Part("keys", keys, "muted", 1, on="tile"),
        Part("trackpad", rect(128, 192, 768, 896, 128), "base", 2, on="tile"),
    ]

SPEC = Spec(
    name="Triggers",
    tile=TILE,
    main=TILE,
    main2=mix(TILE, BIRCH, 0.5),
    main3=mix(TILE, CHAR, 0.3),
    accent=ACCENTS["lingonberry"],
    muted=mix(TILE, BIRCH, 0.6),
    parts=parts,
    print=Print(plate="Triggers.jpg", crop=(720, 2180, 1200),
                erase=[(730, 2500, 160, 220), (1330, 3290, 100, 100), (1880, 2620, 60, 340)],
                on="trackpad", clear=["fingertips", "trails"],
                plant=("Aconitum napellus", "monkshood")),
)
