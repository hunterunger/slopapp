"""Download the chosen Köhler plates (BHL scans via Wikimedia Commons), slowly, with backoff."""
import json, os, time, urllib.request, urllib.error
meta = json.load(open("commons-koehler-meta.json"))
want = {"Awake": "COFFEA arabica", "Dropper": "Roter Fingerhut", "Paper": "Lein. A B", "Commit": "Traubeneiche",
        "Switchboard": "Hopfen", "Tidy": "Wurmfarn", "Clips": "Pfefferminze", "Snapper": "Malva silvestris"}
UA = {"User-Agent": "slopapp-icon-lab/0.1 (open-source icon research; github.com/hunterunger/slopapp)"}
src = json.load(open("sources.json")) if os.path.exists("sources.json") else {}
time.sleep(40)
for app, key in want.items():
    t, m = next((t, m) for t, m in meta.items() if key in m["desc"])
    assert m["lic"].lower().startswith("public domain"), (app, m["lic"])
    out = f"raw/{app}.jpg"
    if not (os.path.exists(out) and os.path.getsize(out) > 100000):
        for attempt in range(8):
            try:
                data = urllib.request.urlopen(urllib.request.Request(m["url"], headers=UA), timeout=120).read()
                open(out, "wb").write(data); break
            except urllib.error.HTTPError as e:
                if e.code != 429: raise
                time.sleep(30 * (attempt + 1))
        time.sleep(10)
    src[app] = dict(file=t, page=m["page"], licence=m["lic"], credit=m["credit"], artist=m["artist"],
                    date=m["date"], description=m["desc"][:200], url=m["url"])
    print(app, os.path.getsize(out), flush=True)
    json.dump(src, open("sources.json", "w"), indent=1, ensure_ascii=False)
print("done")
