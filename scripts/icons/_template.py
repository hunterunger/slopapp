"""<App>: <what the tile is>. Rules: brand/ICONS.md. Started by `herbarium.py new <App>`."""
from herbarium import *

TILE = TILES["sand"]             # this app's own tile colour (`herbarium.py tiles` lists the free ones)

def parts():
    return [
        # Part(name, white artwork, role, depth, on=<role it sits on>)   depth 0 = front
        Part("thing", rect(128, 192, 768, 960, 128), "surface", 2, on="tile"),
        Part("actor", pill(256, 352, 512, 128), "accent", 0, on="surface"),
    ]

SPEC = Spec(
    name="<App>",
    tile=TILE,
    main=TILE,                    # usually the tile colour, or a strong colour for the hero part
    main2=mix(TILE, BIRCH, 0.5),  # lighter
    main3=mix(TILE, CHAR, 0.3),   # deeper
    accent=ACCENTS["lingonberry"],  # pick one that contrasts with the tile
    muted=mix(TILE, BIRCH, 0.7),  # a quiet tint for secondary parts
    parts=parts,
    # herbarium.py plates <word>, then herbarium.py fetch <App> "<Commons file>"
    print=Print(plate="<App>.jpg", crop=(0, 0, 1000), on="ground", plant=("<Botanical name>", "<common name>")),
)
