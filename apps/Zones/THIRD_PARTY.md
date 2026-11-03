# Third-party data in Zones

## GeoNames city list

`Sources/ZonesCore/Resources/cities.tsv.deflate` is derived from the GeoNames geographical
database:

- Source: https://www.geonames.org, files `cities15000.zip` and `admin1CodesASCII.txt` from
  https://download.geonames.org/export/dump/
- License: Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0/
- Attribution: "City names from GeoNames (geonames.org), licensed under CC BY 4.0."
  Shown in the app's About window and Settings → About, and in the README.
- Changes: trimmed to name, folded search keys (ASCII name and selected alternate names),
  country code, region name, population and time zone identifier; sorted by population;
  compressed (raw DEFLATE). Coordinates and other fields were dropped. Built by
  `Tools/build-cities.py`.
- GeoNames provides the data "as is" without warranty.

Time zone rules are not bundled: they come from macOS's time zone database.

The app's own code is MIT licensed, like the rest of Slopapp.
