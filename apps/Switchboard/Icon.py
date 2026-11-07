"""Switchboard: one track in, a symmetric fork out, the chosen route lit. Transit-map bends (r 256).
Print: hops (a climbing bine) on the ground."""
from herbarium import *

def parts():
    y0, jx = 512, 256
    return [
        Part("switch", disc(jx, y0, 128), "accent", 0, on="tile"),
        Part("lit", stroke(f"M-64,{y0} L{jx},{y0}", W1) + stroke(bend_route(jx, y0, 192), W1), "base", 1, on="tile"),
        Part("unlit", stroke(bend_route(jx, y0, 832), W1), "muted", 2, on="tile"),
    ]

SPEC = Spec(
    name="Switchboard", tile=TILES["fjord"],
    main="#5D7E9A", main2="#B8C8D5", main3="#3E5870", accent=ACCENTS["ochre"], muted="#93ABBE",
    parts=parts,
    print=Print(plate="Switchboard.jpg", crop=(380, 450, 1000),
                plant=("Humulus lupulus", "hops")),
)
