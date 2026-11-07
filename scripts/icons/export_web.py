#!/usr/bin/env python3
"""Export the herbarium app icons and botanical prints for the website.

    python3 scripts/icons/export_web.py            # every app with an Icon.py
    python3 scripts/icons/export_web.py Clips Tidy # just these (herbarium.json still lists all)

Renders each app's committed apps/<App>/AppIcon.icon with ictool (Default and Dark looks), so the
website always shows the icon the app ships with. Run it after changing an Icon.py (and building,
which regenerates the AppIcon.icon). Needs Xcode 26+ (ictool) and ImageMagick (WebP).

Writes
  web/public/icons/<slug>.webp, <slug>-dark.webp   app icons, 256 px (Default / Dark renditions)
  web/public/prints/<slug>.webp                    the app's plate as a white-on-transparent mask, 768 px
  web/src/generated/herbarium.json                 slug -> plant, plate number, tile colour, files
"""
import json, os, re, subprocess, sys, tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import herbarium  # noqa: E402

WEB = os.path.join(herbarium.ROOT, "web")


def main(only):
    icons_out, prints_out = os.path.join(WEB, "public", "icons"), os.path.join(WEB, "public", "prints")
    os.makedirs(icons_out, exist_ok=True)
    os.makedirs(prints_out, exist_ok=True)
    sources = json.load(open(herbarium.SOURCES))
    specs, broken = herbarium.load_all()
    for app, err in broken.items():
        print(f"skip {app}: Icon.py doesn't load ({err})")
    meta = {}
    with tempfile.TemporaryDirectory() as tmp:
        for app, spec in specs.items():
            if herbarium.check(spec, specs.values())[0]:
                print(f"skip {app}: fails the style check (herbarium.py check {app})")
                continue
            doc = herbarium.icon_doc(app)
            if not os.path.isdir(doc):
                print(f"skip {app}: no apps/{app}/AppIcon.icon (herbarium.py build {app})")
                continue
            slug = app.lower()
            if not only or app in only:
                for rendition, name in (("Default", f"{slug}.webp"), ("Dark", f"{slug}-dark.webp")):
                    png = os.path.join(tmp, f"{app}-{rendition}.png")
                    herbarium.ictool(doc, png, rendition, 256, 2)
                    subprocess.run(["magick", png, "-resize", "256x256", "-quality", "90", "-define",
                                    "webp:alpha-quality=100", os.path.join(icons_out, name)], check=True)
                # the mask only needs alpha: drop to 768 px and a lossy alpha channel
                subprocess.run(["magick", herbarium.print_png(spec), "-resize", "768x768", "-quality", "60",
                                "-define", "webp:alpha-quality=55", "-define", "webp:method=6",
                                os.path.join(prints_out, f"{slug}.webp")], check=True)
            src = sources.get(app, {})
            plate = re.search(r"Plate ([^)]+)\)", src.get("file", ""))
            latin, common = spec.print.plant or ("", "")
            meta[slug] = {"app": app, "plant": latin, "common": common,
                          "plate": plate.group(1) if plate else None, "tile": spec.tile,
                          "icon": f"/icons/{slug}.webp", "iconDark": f"/icons/{slug}-dark.webp",
                          "print": f"/prints/{slug}.webp", "source": src.get("page")}
    out = os.path.join(WEB, "src", "generated", "herbarium.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"exported {len(only) if only else len(meta)} app(s); {len(meta)} in {os.path.relpath(out, herbarium.ROOT)}")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
