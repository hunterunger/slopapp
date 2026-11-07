# Icon lab

The app icon style is **locked**: Nordic herbarium, specified in [`../ICONS.md`](../ICONS.md).
It has shipped: the generator is `scripts/icons/herbarium.py`, each app's spec is
`apps/<App>/Icon.py`, and the plates are in [`../plates/`](../plates/). Draw new icons there,
not here.

What's left here is the exploration history (rounds 1–5 and the herbarium round that was
chosen). It's not the spec; don't build new icons from it.

| Path | What |
|---|---|
| `lab.py`, `kit.py`, `r2_*.py`, `r3.py`, `r4.py`, `r5.py`, `sheet.py` | Rounds 1–5 |
| `construction/`, `glyphs/`, `compare-*.html` | Construction overlays, early glyphs, comparison pages |
| `bhl/` | The first plate downloads and the Köhler index (`brand/plates/` has the shipped copies) |
| `docs/`, `renders/`, `sheets/`, `web/`, `grain/`, `bhl/raw`, `bhl/tex`, `bhl/grid` | Renders and downloads; local only (see `.gitignore`, ~500 MB) |
