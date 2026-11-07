"""Zones: a desk globe, close up and front-on. It fills the tile and runs off three edges; its
meridian ring arcs over the top and holds the axis at the north pole. Meridians, the equator and one
parallel are cut through it, and one zone between two meridians is lit. Print: star anise on the
globe (the land), cleared around the lit zone.

Meridians are arcs through both poles: discs centred on the equator at 512 +/- 672, r 928 (they
cross the equator at 256 and 768, 30 degrees of longitude on an r-640 globe). Parallels are
straight lines seen front-on: the equator, and 30 degrees north at y = 832 - 320."""
from herbarium import *

CX, CY, R = 512, 832, 640                      # north pole at (512, 192)
OUTSIDE = ring(CX, CY, 1600, 1600 - R)         # everything beyond the globe

def parts():
    # each slit sits just outside its meridian's disc, so the lit zone ends on a clean edge
    slits = (ring(CX - 672, CY, 960, H) + ring(CX + 672, CY, 960, H)
             + stroke(f"M{CX},0 L{CX},1088", H)
             + stroke(f"M-64,{CY} L1088,{CY}", H) + stroke(f"M-64,{CY - 320} L1088,{CY - 320}", H))
    zone = cut(disc(CX - 672, CY, 928), OUTSIDE + rect(-64, -64, CX + 64, 1152) + slits, "zone")
    return [
        Part("zone", zone, "accent", 0, on="surface"),
        Part("globe", cut(disc(CX, CY, R), slits, "slits"), "surface", 1, on="tile"),
        Part("pin", rect(480, 96, 64, 128), "main3", 1, on="tile"),
        Part("meridian", ring(CX, CY, R + 128, W2), "main3", 2, on="tile"),
    ]

SPEC = Spec(
    name="Zones", tile=TILES["mist"],
    main="#9FB3C2", main2="#CAD2D5", main3="#5F7180", accent=ACCENTS["clay"], muted="#CAD2D5",
    dark={"main3": "#8C9AA4"},
    parts=parts,
    print=Print(plate="Zones.jpg", crop=(200, 150, 1000), on="globe", clear=["zone"],
                erase=[(1120, 1040, 80, 110), (200, 540, 90, 140), (200, 960, 110, 190), (200, 170, 40, 100)],
                plant=("Illicium verum", "star anise")),
)
