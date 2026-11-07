"""Slopapp (the launcher): the owner's stacked-layers mark, the collection's front sheet over the
one behind it, drawn in the herbarium finish. The brand mark, so its artwork is the owner's own SVG
(isometric, off the 32 grid) rather than grid construction. Print: linden on the front sheet;
Linnaeus took his name from the linden tree."""
from herbarium import *

# The owner's artwork (2000 x 2000 artboard) placed as in the original icon: 0.49, centred.
PLACE = 'transform="translate(22 22) scale(0.49)"'
SKEW = 'transform="matrix(0.958822,-0.606118,0.958822,0.606118,-1202.183393,1145.091684)"'
BACK = "M1601.142,1489.151C1563.427,1571.294 1480.418,1628.397 1384.177,1628.397L906.968,1628.397C775.279,1628.397 668.364,1521.482 668.364,1389.792L668.364,912.583C668.364,816.343 725.466,733.334 807.61,695.618C793.718,725.874 785.971,759.528 785.971,794.976C702.29,994.769 730.068,1143.188 785.971,1272.185C785.971,1403.875 892.886,1510.79 1024.575,1510.79C1149.397,1588.848 1315.126,1596.706 1501.784,1510.79C1537.233,1510.79 1570.886,1503.043 1601.142,1489.151Z"
FRONT = "M1867.775,667.589L1867.775,1144.798C1867.775,1276.488 1760.86,1383.403 1629.171,1383.403L1151.962,1383.403C1020.273,1383.403 913.358,1276.488 913.358,1144.798L913.358,667.589C913.358,535.9 1020.273,428.985 1151.962,428.985L1629.171,428.985C1760.86,428.985 1867.775,535.9 1867.775,667.589Z"

def art(d):
    return f'<g {PLACE}><g {SKEW}><path d="{d}" fill="#FFF"/></g></g>'

def parts():
    return [
        Part("front", art(FRONT), "base", 1, on="tile"),
        Part("back", art(BACK), "accent", 2, on="tile"),
    ]

SPEC = Spec(
    name="Slopapp", tile=TILES["moss"],
    main=TILES["moss"], main2=mix(TILES["moss"], BIRCH, 0.5), main3=mix(TILES["moss"], CHAR, 0.3),
    accent=ACCENTS["ochre"], muted=mix(TILES["moss"], BIRCH, 0.7),
    parts=parts,
    print=Print(plate="Slopapp.jpg", crop=(250, 520, 1100), erase=[(1160, 1150, 150, 280)],
                on="ground", clear=["front", "back"], plant=("Tilia cordata", "small-leaved linden")),
)
