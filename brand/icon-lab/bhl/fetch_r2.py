"""Fetch plates for the second batch of apps through herbarium.fetch_plate (licence-checked, with backoff)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import herbarium
meta = json.load(open(herbarium.INDEX))
def find(pred):
    return next(t for t, m in meta.items() if pred(m["desc"]))
want = {
    "Convert": find(lambda d: d.startswith("Kakaobaum")),
    "Crate": find(lambda d: d.startswith("Korkeiche")),
    "Devkit": find(lambda d: d.startswith("Echte Salbei")),
    "Dictate": find(lambda d: d.startswith("Echter Eibisch")),
    "Focus": find(lambda d: d.startswith("Lavendel")),
    "Iconsmith": find(lambda d: "ceatifo" in d),
    "Ruler": find(lambda d: d.startswith("Anis.")),
    "Specimen": find(lambda d: d.startswith("Stockrose")),
    "Squish": find(lambda d: d.startswith("Punica")),
    "Tally": find(lambda d: d.startswith("Schwarzer Senf")),
    "Zones": find(lambda d: d.startswith("Japanischer Sternanis")),
}
for app, title in want.items():
    if os.path.exists(os.path.join(herbarium.PLATES, f"{app}.jpg")):
        print(app, "already here", flush=True); continue
    herbarium.fetch_plate(app, title)
    sys.stdout.flush()
    time.sleep(12)
print("done", flush=True)
