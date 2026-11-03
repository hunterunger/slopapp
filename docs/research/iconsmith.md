# Iconsmith research (inspired by Image2icon)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Image2icon 2.17 (943)**, Setapp build (`net.shinyfrog.image2icon-setapp`,
> /Applications/Setapp/Image2icon.app, read-only), plus the developer's site and how-to
> pages, the Mac App Store listing and version history (latest public release is 2.18, Feb
> 2023), press reviews, and Apple's current icon documentation (asset catalogs, Icon
> Composer, HIG). We study how it works so we don't reinvent the wheel. We never copy its
> name, icons, artwork, wording, sounds or signature visuals.
>
> **How the original was explored.** It wasn't running. Launched twice (once via
> `scripts/drive launch`, once via `open`); both times the Setapp licensing check failed with
> a Setapp error (-401) alert and the app quit when the alert was dismissed. Getting past
> it would have meant touching the Setapp login/subscription state, so I didn't. What I
> could read without that: the full main menu with shortcuts (`tree --menu` while the alert
> was up), the bundle's Info.plist, entitlements, default preferences, Shortcuts intent
> definitions, and the control labels/layout frames in its compiled interface files. The UI
> flows below are reconstructed from those plus the official docs and reviews; anything
> inferred is marked *(inferred)*. No settings were changed, no icons were set, nothing
> was exported, no screenshots of content were taken. App confirmed quit at the end.

## The job

Someone has a picture (a logo, a photo, an SVG from a designer, a screenshot of a game
cover) and wants it to *be an icon*: the icon of an app they're building, a website
favicon, or the icon of a folder or drive on their own Mac so it's findable at a glance.
The hard parts they don't want to learn are Apple's icon grid, the dozen sizes and file
names each target needs, the Contents.json that Xcode expects, and the arcane ways macOS
stores custom file icons. "Done" is either a Finder folder that now shows the picture, or
a ready-to-drop `.icns` / `AppIcon.appiconset` / favicon folder that looks sharp at 16 px
and at 1024 px. **The one interaction that matters: drop an image → see it as an icon in
the shape you need → drop a folder onto it (icon applied) or press Export (files written,
revealed in Finder).**

## Who and when

- An indie/app developer needs an `AppIcon` for a new Xcode project, or an `.icns` for a
  script-built app bundle (exactly what our own `scripts/icongen.swift` does for Slopapp).
- A web developer needs favicon.ico + apple-touch-icon + manifest icons for a site.
- Anyone organizing their Mac: colour-coded or picture-labelled project folders, a
  recognisable external drive or USB stick, a custom icon for a script/alias.
- Restoring: a folder or drive still shows an icon someone set years ago and they want
  the default back.
- Pulling the icon out of an app or file as a PNG (for docs, a blog post, a slide).

Frequency: bursty. Developers use it at project start and when rebranding (a few times a
year, 1–5 min each). Folder customizers use it in sessions (10–30 folders at once), then
not for months. Nobody opens Settings; it must work from defaults.

## The original at a glance

| | Image2icon 2.17 |
|---|---|
| Window | Fixed, compact: a ~140 pt template sidebar on the left (live previews of your picture in each template, locked ones with a padlock) and a ~405×544 pt main panel. Custom-drawn chrome, Avenir fonts, striped backgrounds. *(from interface files)* |
| Main panel | A big circular drop area that becomes the icon preview. Bottom tab switch between **Create** and **Restore** modes. A bottom bar of round buttons: remove background (colour-pick "lens" + tolerance slider), text/emoji, template settings, share, clear, and a big **Export** button. A batch button with a counter appears when several images are loaded. |
| Two-step apply | After an image is loaded, the hint changes to "now drop a file or folder to set the icon"; dropping a folder on the preview applies the icon immediately. A timer resets that state (a reviewer reports the second drop sometimes fails "if the timing is off"). |
| Templates (~35) | Original (as-is), Square, Round (bordered/full), Squircle, "Big Sur App", iOS, iMessage, Android, Folder (full, centered, engraved, dark centered, dark engraved, documents, favicon folder), Document (full, centered), Drive, Silver Drive, USB, SD card, CD/DVD/Blu-ray cases and discs, Vinyl, Mini Disc, Floppy, NES/Game Boy cartridges, Film frame, Polaroid, Poster, Stamp, Stack, Tilted, Slip cover, Booklet, vCard, Mail, Watch, Christmas, Archive. Folder art is bundled per macOS era (Mavericks, Yosemite, El Capitan, Sierra, Big Sur, dark). |
| Template settings | Popover: Zoom, Rotation, Horizontal offset, Vertical offset (each a slider with −/+ and a per-row reset), Background colour, Reset All. |
| Text / emoji | Popover: a text field ("type your text or emoji") with emoji button, Typeface, Weight, Size (with auto-fit), Colour, Alignment, Reset, Cancel/OK. |
| Export | A popover with 9 targets: Folder, ICNS, iOS, Android, Favicon, Iconset, ICO, PNG, JPG (last three Pro). iOS/Android/Favicon show inline size checklists; Iconset has a popup (macOS iconset vs iOS appiconset); PNG/JPG have an "Image size" slider (default 1024×1024). Then a save panel. |
| Restore mode | Drop files/folders → their default icons come back. |
| Pricing | Mac App Store: free with IAPs (everything $9.99; exports $5.99; templates $5.99). Setapp: all unlocked. |

### Export details (from the bundle's defaults and labels)

| Target | What it writes | Defaults |
|---|---|---|
| ICNS | `icon.icns` | — |
| Iconset | macOS `icon.iconset` folder, or an iOS `.appiconset` with Contents.json | macOS |
| Folder | An empty folder (or one per batch image) that carries the custom icon, to copy from via Get Info | — |
| iOS | Per-size PNGs + Contents.json in **legacy per-size layout** (iPhone 29/40/57/60/120/180, iPad 20–76/83.5, watch 24–196, iMessage). Warns "your image has transparencies; the icons can show a white background". | All size groups on; **"rounded" on** (pre-rounds iOS icons) |
| Android | Launcher 48/72/96/144/192 (mdpi…xxxhdpi) + 512 Play Store | All on; rounded corners off |
| Favicon | `favicon.ico` (16+32), 32 Chrome, 57/72/114/120/144/152/180 Apple touch "precomposed", 192 Chrome Android, 36–192 manifest PNGs, `manifest.json`, sample `index.html` | All on |
| ICO | Windows .ico, 256 px with alpha | — |
| PNG / JPG | Single image at the slider size | 1024 |

The installed build was compiled against the macOS 11.3 SDK (Xcode 13). Its iOS output
predates Xcode 14's single-size 1024 icons and iOS 18's dark/tinted variants, and its
favicon set targets iOS 6 and IE10. 2.18 (Feb 2023) only added "Xcode 13 iOS and new
Android icon support". The product looks unmaintained since.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Load a source image | Drop on the circle, ⌘O, or "Use Blank Image". Accepts JPG, PNG, WebP, PSD, SVG, PDF and any file/folder (uses its icon). | **must** | `DropZone` + ⌘O. Formats: anything `NSImage`/ImageIO decodes, incl. SVG and PDF (render vectors at each pixel size like `icongen.swift`). One source at a time in the editor. |
| 2 | Live preview in the chosen shape | Big preview + sidebar of every template rendered with your picture. | **must** | One large preview + a compact shape picker (segmented/grid with live thumbnails). Preview at 1024 and at 32/16 px side by side, so small-size legibility is visible before export. |
| 3 | Shapes / masks | ~35 templates, many novelty objects. | **must** (5) | v1 shapes: **macOS app** (Apple grid tile with shadow, from `icongen.swift`), **Square** (full bleed, for iOS/Xcode where the system masks), **Circle**, **As-is** (just squared and padded, keeps alpha), **Folder** (#9). |
| 4 | Padding / zoom / offset | Zoom slider, H/V offset sliders, rotation slider, per-row reset. | **must** (zoom + offset) | Padding slider (or zoom), drag the image in the preview to offset, double-click to re-centre. Fit vs Fill toggle for non-square sources. Rotation: **later**. |
| 5 | Background fill | Colour well in template settings. | **must** | None (transparent) / Colour (system colour well) / Auto (sampled from the image edge). Forced opaque for iOS/watch (App Store rejects alpha), with a one-line notice. |
| 6 | Export `.icns` | Export > ICNS (⌘2), File > Save As .icns (⇧⌘S). | **must** | Each size rendered at its own pixel size, then `iconutil`. |
| 7 | Export `.iconset` | Export > Iconset (⌘6). | **must** | Same renderer, keep the folder. |
| 8 | Xcode asset catalog `AppIcon.appiconset` | iOS appiconset, legacy per-size layout, pre-rounded by default. | **must** | Current layout: **macOS** all ten sizes (16–512 @1x/@2x, `idiom: mac`); **iOS** single-size 1024 (`idiom: universal, platform: ios`); **watchOS** single-size 1024. Platform checkboxes, macOS+iOS on by default. Never pre-round iOS/watch (the system masks). |
| 9 | Folder icon template | Bundled folder art per macOS era, image placed centred/full/engraved. | **must** | Composite onto the **live system folder icon** (`NSWorkspace.icon(for: .folder)`) so it always matches the running macOS and accent. Picture placed in the folder's front panel; "engraved" look later. No bundled artwork. |
| 10 | Set icon on files/folders | Drop target(s) onto the preview after loading an image (timed state). | **must** | A persistent "Apply to…" well/button: drop or choose any number of files, folders, volumes. `NSWorkspace.setIcon(_:forFile:)`. Per-target result. |
| 11 | Restore default icon | Restore tab: drop files/folders. Shortcuts action too. | **must** | A "Remove Custom Icon" mode/command: `setIcon(nil, forFile:)`. Works on many at once. |
| 12 | Undo apply/restore | None. | **must** | ⌘Z: snapshot each target's previous custom icon (`URLResourceValues.customIcon`) before writing; undo restores it (or clears it). |
| 13 | Favicons | 17 files incl. iOS 6 / IE10 sizes, manifest, sample HTML. | **should** | Modern set: `favicon.ico` (16/32/48), `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (art inside the 409 px safe zone), `apple-touch-icon.png` (180, opaque), `manifest.webmanifest`, plus an HTML snippet copied to the clipboard. Optional `icon.svg` when the source is SVG. |
| 14 | PNG export at a size | Pro: slider size. | **should** | Single PNG, size popup (1024 default). Also ⌘C copies the rendered icon as PNG. |
| 15 | Dark / tinted variants (iOS 18+) | None. | **later** (deferred from should) | Optional second source for Dark (transparent background) and an auto-generated grayscale Tinted; written as `appearances: luminosity dark/tinted` entries. |
| 16 | Grab an icon from an app/file | Drop an app or any file; its icon becomes the source. | **should** | Cheap: `NSWorkspace.icon(forFile:)`, largest rep. Lets people export an app's icon as PNG. |
| 17 | Batch | Drop many images; batch button with counter; export all with the same template. | **later** (deferred from should) | Many images in → SlopKit `FileQueue`, one row per image, each exported with the current shape/options to its own output folder. |
| 18 | Paste image (⌘V) as source | Not seen. | **should** | Cheap and common (copied logo from a browser). |
| 19 | Windows `.ico` | Pro, 256 px with alpha. | **should** | ImageIO writes ICO; multi-size 16–256. Shares code with favicon.ico. |
| 20 | Background removal | Colour-pick "lens" + tolerance slider (chroma key). | **later** | Vision subject lifting (`VNGenerateForegroundInstanceMaskRequest`, on-device) is far better than chroma key. One toggle: "Remove background". |
| 21 | Text / emoji on icon | Popover: text, typeface, weight, size, colour, alignment. | **skip** (owner) | macOS 26 Finder already puts an emoji/SF Symbol on folders ("Customize Folder"). Revisit if people ask for text labels. |
| 22 | Icon Composer `.icon` bundle | None. | **later** | A `.icon` is a folder with `icon.json` + `Assets/`; Xcode's own template is `{fill, groups, supported-platforms}`. The format is undocumented; a single-layer export is cheap but may break with Xcode updates. See open questions. |
| 23 | Android launcher icons | Mipmap 48–192 + 512 Play Store; rounded option. | **later** | If added: legacy mipmaps + 512 Play icon + adaptive foreground/background layers (108 dp canvas, 66 dp safe zone). Cheap renderer-wise, but outside Mac-first scope. |
| 24 | Shortcuts / App Intents | Set Custom Icon (image + file/folder + template), Restore Original Icon, Open With File. | **later** | App Intents: "Set Icon", "Remove Custom Icon", "Make Icon Files". Natural fit, after v1. |
| 25 | Finder Quick Action | None. | **later** | "Remove Custom Icon" and "Use as Icon for…" from Finder's context menu. |
| 26 | Apply icons to apps (`.app`) | Works for user-writable apps; not for system/App Store apps. | **later** (owner) | The macOS 26 use case: give an app jailed in the grey squircle a custom icon. Needs App Management permission; root-owned App Store apps need admin; macOS's own apps can't be changed; updates wipe it. See open questions. |
| 27 | Volume icons | Applies to drives; "external drives may require Finder". | **should** | `setIcon` on a mount point writes `.VolumeIcon.icns`. Read-only, FAT/exFAT and network volumes fail with a clear message. |
| 28 | Export "Folder" (empty folder carrying the icon) | Export > Folder (⌘1). | **skip** | A workaround for "how do I apply this elsewhere"; applying directly + `.icns` export covers it. |
| 29 | Novelty templates (CD, vinyl, floppy, cartridges, Polaroid, stamp…) | ~25 bundled artworks. | **skip** | Artwork-heavy, the original's signature look, rarely the job. |
| 30 | JPG export | Pro. | **skip** | Icons need alpha; PNG covers "one image". |
| 31 | Share menu | Share button. | **later** | Reveal in Finder + drag-out of the preview cover it. |
| 32 | Drag the result out | Exports are file promises on the export buttons *(inferred from pasteboard types)*. | **later** (conflicts with drag-to-move) | Drag the preview to Finder → `.icns` (or PNG with ⌥). Cheap with `NSItemProvider`/file promise. |
| 33 | Upsell, rating prompts, feedback window, updater | IAP window, "Rate", feedback, Sparkle feed, App Center SDK. | **skip** | Not our model. No network. |
| 34 | x-callback URL scheme | `image2icon://x-callback-url/…` (open files, apply, restore, help). | **skip** | App Intents cover automation. |
| 35 | Localization | 9 languages. | **later** | English first, strings localizable. |

## Key flows

### Flow 1: icon files from an image (main job)
1. Open Iconsmith: the window is a `DropZone` ("Drop an image") with "or click to choose"
   (⌘O). ⌘V pastes an image.
2. Drop `logo.svg`. The preview appears immediately in the default shape (**macOS app**),
   with 1024 / 32 / 16 px renders side by side. Shape picker, Padding slider, Background
   control sit beside or under the preview (no modal).
3. Drag the art in the preview to nudge it; double-click re-centres.
4. Choose what to export: a row of checkboxes or a menu (**.icns**, **Iconset**, **Xcode
   App Icon**, **Favicons**, **PNG**). Remembered between launches. Default: .icns.
5. **Export** (⌘E): a save panel defaulting to the source image's folder; Iconsmith writes
   `<name>.icns` / `<name>.iconset` / `AppIcon.appiconset` / `<name> Favicons/`, then
   reveals it in Finder. Name collisions get " 2", never overwrite silently.

The original does the same in a popover per target, then a save panel per target.

### Flow 2: custom icon on folders (the original's most-reviewed use)
1. Drop a photo. Pick the **Folder** shape: the photo sits on the current macOS folder.
2. Drop one or more folders on the **Apply to…** well (or click it and choose). The icons
   change in Finder at once; the well lists each target with a check or an error.
3. Not happy: ⌘Z puts back what each folder had before (including an older custom icon).
4. The source stays loaded; drop more folders any time. No timer.

Original: after loading, the preview itself becomes the drop target for a short while.

### Flow 3: restore default icons
1. Edit > Remove Custom Icon… (or a "Remove Custom Icons" mode of the Apply well), drop or
   choose files/folders/volumes. Works without a source image loaded.
2. Each target shows done / not changed (no custom icon) / error. ⌘Z re-applies.

Original: a separate "Restore" tab with its own drop area; failures say the user isn't
allowed and link to a manual how-to (Get Info → select icon → Delete).

### Flow 4: Xcode app icon
1. Drop 1024 px art. Pick **Square** (iOS) or **macOS app** (macOS).
2. Export > Xcode App Icon: platform checkboxes (macOS, iOS, watchOS), optional Dark
   source well and "Tinted" checkbox (iOS).
3. Writes `AppIcon.appiconset/` with Contents.json; drop it into `Assets.xcassets`.
   Alpha is flattened onto the background for iOS/watch, with a notice when that happened.

Note: if a project uses an Icon Composer `.icon` file, Xcode prefers it over the asset
catalog AppIcon (Apple docs). The asset catalog is still the format for everyone not
designing in layers.

### Flow 5: first run
1. No onboarding, no permission prompts. The empty window explains itself.
2. Permissions only appear when needed (see below), in place, with one sentence.

Original: no onboarding; the Setapp build runs a license check first (that is what blocked
this study); the App Store build opens with locked templates and an IAP window.

## Settings inventory

The original has **no Settings window** at all (no Preferences item in the app menu). Its
only preferences are the inline size checklists in the export popover:

| Original setting | Default |
|---|---|
| iOS: iPhone, iPad, Apple Watch, iMessage size groups | all on |
| iOS: rounded corners | **on** (wrong for Xcode; the system masks) |
| Android: 48, 72, 96, 144, 192, 512 | all on |
| Android: add rounded corners | off |
| Favicon: 16/32 ico, 32 Chrome, 57, 72, 114, 120, 144, 152, 180, 192 | all on |
| PNG/JPG export size | 1024 px |
| Hide share dialog | off |

Ours (defaults chosen so Settings is rarely opened; options live in the window):

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Last shape, padding, background | macOS app, Apple grid, none | — | Remembered, not in Settings |
| Export targets | .icns | .icns, Iconset, Xcode App Icon, Favicons, PNG | Remembered in the window |
| Xcode platforms | macOS + iOS | macOS, iOS, watchOS | In the export options |
| Export location | Ask (save panel at the source's folder) | Ask / Next to the source image | Settings > General |
| Reveal in Finder after export | on | on/off | Settings > General |
| About | — | — | Settings > About |

## Menus and shortcuts

**Original** (Setapp build):

- **Image2icon**: About, Unlock Pro features, Rate, Check for Updates, Services, Hide ⌘H,
  Hide Others ⌥⌘H, Show All, Quit ⌘Q. *(No Settings.)*
- **File**: Open… ⌘O, Use Blank Image, Close ⌘W, Save As .icns ⇧⌘S.
- **Edit**: standard (Undo/Redo/Cut/Copy/Paste… all disabled in the empty state).
- **Export**: Folder ⌘1, ICNS ⌘2, iOS ⌘3, Android ⌘4, Favicon ⌘5, Iconset ⌘6, (Pro) Windows
  ICO ⌘7, PNG ⌘8, JPG ⌘9.
- **Window**: standard + Unlock Pro features.
- **Help**: Support ⌘?, Website, How To Apply .icns Files, How To Restore Original Icons,
  Create The Best .icns Files, Unlock Pro, Rate.

**Ours** (proposal):

- **Iconsmith**: About Iconsmith, Settings… ⌘,, Hide/Quit.
- **File**: Open Image… ⌘O, Export ⌘E, Export As > (.icns ⇧⌘1, Iconset ⇧⌘2, Xcode App
  Icon ⇧⌘3, Favicons ⇧⌘4, PNG ⇧⌘5), Close ⌘W. *(Built as ⌥⌘1–⌥⌘6: ⇧⌘3–6 are macOS
  screenshot shortcuts.)*
- **Edit**: Undo/Redo (apply/restore and editor changes), Copy (rendered icon as PNG) ⌘C,
  Paste (image as source) ⌘V, Apply Icon to… ⌘J *(choose files)*, Remove Custom Icon… ⇧⌘J.
- **View**: Shape > (macOS App ⌘1, Square ⌘2, Circle ⌘3, As Is ⌘4, Folder ⌘5), Reset
  Position ⌘0.
- **Help**: Iconsmith Help (README link).

## Permissions and system integration

The original is **sandboxed** with only user-selected read/write, so it can change icons
only on items the user dropped or picked; it links an analytics/crash SDK and has a
network entitlement (Setapp provisioning, update feed). Shortcuts intents: Set Custom Icon,
Restore Original Icon, Open With File. URL scheme `image2icon://`. Registers as an
"Alternate" editor for **all file types** (so it appears in Open With for everything).

What Iconsmith needs, feature by feature (our apps are not sandboxed):

| Feature | Permission | Notes |
|---|---|---|
| Read source image, write exports | none | Files come from drop/open panel/save panel, which macOS treats as user consent (incl. Desktop/Documents/Downloads). |
| Set/remove icons on files and folders in the home folder | none | Same: dropped or chosen targets. `setIcon` requires the item to exist and be writable. Files stored as a resource fork; folders get a hidden `Icon\r` file; both set the custom-icon Finder flag. |
| Removable / network volumes | TCC "Removable Volumes" / "Network Volumes" may prompt on first write | Prompt is macOS's own; we explain failure if denied. FAT/exFAT/SMB may not keep the icon. |
| Volume icon | write access to the volume root | Writes `.VolumeIcon.icns`. Not possible on the system volume. |
| Icons on `.app` bundles | **App Management** (Privacy & Security, macOS 13+) | Without it, macOS blocks modifying another developer's app. App Store apps are root-owned → also need admin rights. Apple's own apps (sealed system volume) can't be changed at all. Custom icon stored as `Icon\r` inside the bundle, outside the code signature, but app updates replace it. Use `PermissionGate` on first app target. |
| Files owned by another user / locked (`uchg`) | none we can get | Fail with a clear error; suggest Get Info. |
| Shortcuts (later) | none | App Intents. |
| Network | none | No network at all. |

## UX patterns worth adopting

- **The picture stays loaded while you apply it to many things.** Load once, then feed it
  targets. (We drop the original's timer; the apply well is always there.)
- **Restore is a first-class mode, not a buried menu item.** People come back to undo
  icon experiments, sometimes years later on folders they didn't customize themselves.
- **Live thumbnails of every shape** so you choose by looking, not by name.
- **Inline size checklists with sensible all-on defaults**; nobody has to know which sizes
  a target needs.
- **Warn, don't block, on transparency** for targets that will show a background.
- **Grab-an-icon-from-anything**: dropping an app/file uses its icon as the source, which
  doubles as an "export this app's icon as PNG" tool.
- **Per-row reset on adjustment sliders** plus a Reset All; easy to experiment.
- **Help menu explains the manual Finder way** (Get Info → paste / Delete) for cases the
  app can't handle (locked items, other users' files).

## What we won't copy, and what we'll do better

- Not copying: name, icon, template artwork (folders, discs, cartridges…), custom
  chrome and fonts, wording, the circle drop target look, paid/upsell flows, rating
  prompts, URL scheme.
- **Current Apple formats.** Single-size 1024 iOS/watchOS asset catalogs, dark and tinted
  variants, macOS 10-size sets; never pre-round iOS icons (the original rounds by default,
  which produces double corners under the system mask). Flatten alpha for iOS.
- **macOS 26 shape.** The "macOS app" shape fills Apple's grid (824 px rounded tile with
  ~100 px margins on a 1024 canvas, superellipse corners, soft shadow; `scripts/icongen.swift`
  already draws it), so exported app icons aren't shrunk into the grey squircle on macOS 26.
  Preview it the way macOS will show it.
- **Folder art that never goes stale.** Compose on the live system folder icon instead of
  shipping art per macOS release (the original carries folder art for six macOS eras).
- **Sharp small sizes.** Render every size at its own pixel size from the source (vectors
  redrawn, rasters resampled with high quality), and show 16/32 px previews before export.
- **No timer on the second drop** (a reviewer's complaint) and **undo** for every icon
  change.
- **Everything included**, short shape list, no padlocks cluttering the list (reviewers
  disliked locked templates crowding the free ones and not being able to try before buying).
- **Modern favicons**: a small current set + an HTML snippet, not iOS 6 / IE10 sizes.
- **No analytics SDK, no network.** The original links an app analytics/crash SDK and
  allows arbitrary network loads.
- Native SwiftUI, user's accent colour, resizable window, full menus, VoiceOver labels.
- Clear errors that say what to do ("Iconsmith can't change apps until you allow App
  Management in System Settings." / "This drive's format doesn't keep custom icons.").

## Edge cases

- **Sources**: non-square (fit vs fill), tiny (< 256 px: warn that large sizes will be
  blurry), huge (8K+, 100 MB PSD: decode with ImageIO thumbnailing, off the main actor),
  SVG with no size/viewBox, multi-page PDF (first page), animated GIF/WebP (first frame),
  `.icns` input (use the largest rep), CMYK / 16-bit / HDR / wide-gamut (convert to sRGB
  8-bit for outputs, Display P3 kept only where the target allows), EXIF orientation,
  corrupted file, a folder/app dropped as source (use its icon), an alias.
- **Transparency**: fully transparent edges with As-is shape; iOS/watch/apple-touch need
  opaque output (fill with background colour; notice when alpha was flattened).
- **Small sizes**: thin strokes vanishing at 16 px; detail-heavy photos; preview at 16/32.
- **Targets**: many at once (100 folders), mixed success, item already has a custom icon
  (undo restores it, not the default), item has macOS 26 "Customize Folder" emoji/symbol
  (check which wins, and that removing our icon leaves theirs), locked files, other users'
  files, read-only volumes, FAT/exFAT/NTFS/SMB volumes, iCloud Drive folders (does `Icon\r`
  sync? test), items in the Trash, symlinks and aliases (apply to the alias file, not the
  original, unless told otherwise), system volume paths, `.app` bundles (App Management,
  admin-owned, Apple apps), the target moved/deleted between drop and apply.
- **Finder refresh**: Finder sometimes shows the old icon; call
  `NSWorkspace.noteFileSystemChanged` and verify by reading the icon back.
- **Exports**: name collisions (append " 2"), destination unwritable, disk full, app quit
  mid-export (write to a temp folder, move into place at the end), non-ASCII names.
- **Permissions revoked mid-use**: App Management or volume access turned off while the
  app is open → per-target error with a Settings link, nothing half-written.
- **Appearance**: preview in light and dark; dark-variant preview; Reduce Motion.
- **Accessibility**: every control labelled; the preview's drag-to-nudge also via arrow keys.
- **Multiple displays / Retina vs non-Retina**: previews render at the screen's scale.

## Our v1 scope

Archetype: **drop-in utility window** (design system 2b). Reuse SlopKit `DropZone`, and
`FileQueue` for the batch/apply lists. Core rendering in `IconsmithCore`, ported from
`scripts/icongen.swift` (grid, superellipse tile, per-size rendering, `iconutil`), with the
file-icon system calls (`setIcon`, custom icon read-back) behind a protocol for tests.

- [x] Drop, choose (⌘O) or paste (⌘V) an image (PNG, JPEG, HEIC, TIFF, SVG, PDF, WebP, PSD); unreadable files give a clear error
- [x] Live preview at 1024 plus 32 and 16 px, updating as options change (also 128 pt; small sizes at screen scale)
- [x] Shapes: macOS app (Apple grid tile + shadow), Square (full bleed), Circle, As-is, Folder (on the live system folder icon)
- [x] Padding/zoom slider, drag (and arrow keys) to offset, double-click/⌘0 to re-centre, fit vs fill for non-square images
- [x] Background: none / colour / auto; forced opaque (with a notice) for iOS and watchOS output
- [x] Export `.icns` that opens in Preview and shows correctly in Finder at every size
- [x] Export `.iconset` that `iconutil` accepts
- [x] Export Xcode `AppIcon.appiconset` (macOS 10 sizes; iOS and watchOS single-size 1024) that Xcode accepts without warnings (`actool` for macosx, iphoneos, watchos: no warnings)
- [x] Apply the current icon to one or many dropped/chosen files, folders and volumes; Finder shows it; per-target result
- [x] Remove custom icons from one or many files/folders/volumes, without a source image loaded
- [x] ⌘Z undoes an apply or remove (restoring any earlier custom icon)
- [x] Export reveals the result in Finder; never overwrites without asking
- [x] Every action in a menu with its shortcut; Settings (General, About)

Should (v1 if cheap): favicons set + HTML snippet, PNG export / ⌘C copy, dark + tinted iOS
variants, grab icon from an app/file, batch export via `FileQueue`, Windows .ico, drag the
result out, `.app` targets behind an App Management `PermissionGate`.

Should status after the build: **done**: favicons + HTML snippet (copied to the clipboard
and written as `head.html`), PNG export (256–2048) and ⌘C, grab icon from an app or folder,
Windows .ico, paste (⌘V), volume icons. **Deferred**: dark/tinted iOS variants (needs a
second-source UI; later), batch export (one picture at a time covers the main flows; later),
drag the result out (conflicts with drag-to-move in the preview; ⌘C and Export cover it),
`.app` targets (owner: later).

## Open questions (decided)

Owner defaults, recorded 2026-11-03:

1. **Icons on apps (`.app`)**: later. It needs App Management and breaks signatures / is
   wiped by updates. Iconsmith refuses `.app` targets with "Changing app icons isn’t
   supported yet."
2. **Icon Composer `.icon` export**: later.
3. **Favicons and Windows .ico**: should, done (both shipped in v1).
4. **Android**: later.
5. **Background removal**: later.
6. **Text/emoji overlay**: skip (macOS 26 Finder's Customize Folder does it).
7. **Default export location**: a save panel opening in the source image's folder (Desktop
   for pasted pictures).

## Sources

- Official site: <https://img2icnsapp.com/>
- How to restore default icons: <http://www.img2icnsapp.com/how-to-restore-icons-default-on-mac/>
- How to change icons: <https://img2icnsapp.com/how-to-change-icons-on-mac/>
- Mac App Store listing, version history, reviews: <https://apps.apple.com/us/app/image2icon-make-your-icons/id992115977?mt=12>
- 2.18 changelog: <https://mac.softpedia.com/progChangelog/img2icns-Changelog-7918.html>
- Review + comments (workflow, two-drop timing complaint, Safari icon locked): <https://eshop.macsales.com/blog/88038-image2icon-makes-it-easy-to-create-custom-mac-icons/>
- Big Sur edition and App Store app limitation: <https://www.ifun.de/image2icon-produziert-icons-in-big-sur-optik-166465/>
- Alternatives: <https://alternativeto.net/software/img2icns/about/>
- Apple, Configuring your app icon using an asset catalog: <https://developer.apple.com/documentation/xcode/configuring-your-app-icon>
- Apple, Creating your app icon using Icon Composer: <https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer>
- Apple HIG, App icons: <https://developer.apple.com/design/human-interface-guidelines/app-icons>
- WWDC25 "Create icons with Icon Composer": <https://developer.apple.com/videos/play/wwdc2025/361/>
- Icon Composer + asset catalog fallback discussion: <https://developer.apple.com/forums/thread/787576>
- `NSWorkspace.setIcon(_:forFile:options:)`: <https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)>
- Where custom icons live (resource fork, `Icon\r`, `.VolumeIcon.icns`): <https://github.com/mklement0/fileicon>
- Custom app icons and code signatures: <https://eclecticlight.co/2019/07/20/how-to-add-a-custom-icon-to-an-app-without-breaking-its-signature/>
- What you can do with apps (App Management, macOS-bundled apps): <https://eclecticlight.co/2025/11/04/what-can-i-do-with-my-apps/>
- macOS 26 Customize Folder and its xattrs: <https://eclecticlight.co/2025/09/18/customising-folders-in-tahoe/>
- macOS 26 squircle "jail" and custom-icon workaround: <https://heise.de/-11075561>, <https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/>
- Modern favicon set: <https://evilmartians.com/chronicles/how-to-favicon-in-six-files-that-fit-most-needs>
- Repo reference renderer: `scripts/icongen.swift`

## Build notes (steps 3–4, 2026-11-03)

### What was built

- `IconsmithCore` (no SwiftUI): `Style` (shapes, background modes, `IconStyle`),
  `Geometry` (Apple's 824/1024 grid and superellipse from `scripts/icongen.swift`, fit/fill
  art rects, folder layout measured from the live folder icon), `Source` (ImageIO decode,
  max 2048 px, upright, normalized to sRGB 8-bit; SVG/PDF/file icons kept as vectors; edge
  analysis), `Renderer` (every size drawn at its own pixel size; opaque output without an
  alpha channel), `Export` + `ExportWriter` (icns via `iconutil`, iconset, Xcode appiconset,
  favicons, PNG, ICO encoder; staged on the destination volume and moved into place),
  `FinderIcons` (`FileIconSystem` protocol, `IconApplier` with before/after snapshots for
  undo/redo, Finder custom-icon flag read from `com.apple.FinderInfo`), `Preferences`.
- App: one `Window` (drop-in utility archetype). Empty state is a SlopKit `DropZone`; the
  editor is preview (left) + inspector (right: Shape grid with live thumbnails, Picture,
  Background) with Format + Export pinned at the bottom of the inspector. Format options
  (Xcode platforms, PNG size) live in the save panel's accessory view, like Preview's
  Export. Two Finder wells along the bottom: **Apply to Files & Folders** and **Remove
  Custom Icons**, with a per-item results list. Previews render on a serial actor off the
  main thread (1024 px in 2–9 ms per shape, release).

### Builder decisions

- **Logos are trimmed.** Pictures with transparent edges are placed by their visible part
  (alpha bounds), with a shape-specific margin (macOS tile 14%, square 12%, circle 18%), so
  a logo with big transparent padding or an app's own icon looks right in every shape.
  **As Is** never trims (output = the picture as drawn). Size 100% always means "fits";
  photos default to Fill, logos to Fit.
- **Automatic background**: the average colour of the picture's border when it's opaque,
  white when it's transparent, on every shape that has an outline (macOS App, Square,
  Circle), so choosing a shape always shows it (changed in blind test round 1). **None**
  keeps the icon transparent; the preview and thumbnails then draw the shape as a dashed
  outline. iOS/watchOS/touch/maskable outputs are always opaque; when
  that meant filling transparency with white, the save panel and the export status say so.
- **Folder shape** composes on `NSWorkspace.icon(for: .folder)` at each size, picture
  clipped to the front panel with softly rounded corners. No bundled folder art.
- **No timer, no modes**: the picture stays loaded; the two wells are always there. Remove
  works with no picture loaded.
- **Undo covers everything**: icon applies/removes (restoring the exact earlier custom
  icon) and every editor change (shape, size, framing, background, moves; one step per
  slider drag). Loading a new picture clears the editor's undo history.
- **Exports never clobber the source**: when the suggested name equals the source file
  (exporting `logo.png` as PNG), it becomes `logo Icon.png`. Replacing an existing export
  (after the save panel asks) moves the old one to the Trash.
- **Copy/Paste**: ⌘C copies the icon (PNG + TIFF), ⌘V loads an image file or image data;
  in other windows (colour panel) they fall through to normal text editing. Exports never
  write the clipboard; favicons get a **Copy HTML** button in the export status line.
- **Own undo stack**: the model owns its `UndoManager` and Edit ▸ Undo/Redo are our own
  commands, so ⌘Z works even when the window isn't key (scripted runs post keys to the
  process). Editor steps and icon changes use separate undo targets; loading a new picture
  drops only the editor steps.
- **`.app` targets refused** (owner decision 1). Locked items, read-only disks, missing
  items and unwritable items are refused before anything is touched, with what to do next.
- **No FileQueue**: applying icons is instant and single-picture; a simple results list
  reads better than a processing queue. No new shared components were needed.
- Settings has General (Show exported files in Finder) and About; no Launch at login (a
  window app you open when needed). Revealing reuses a Finder window already showing the
  folder (`activateFileViewerSelecting`; 8 exports in round 0 left one "pictures" window).
- Test/env overrides: `ICONSMITH_ALLOWED_ROOT` (icon changes only inside that folder; the
  ⌘J/⇧⌘J choosers start there), `ICONSMITH_PASTEBOARD=<name>` (⌘C, ⌘V and Copy HTML use a
  named pasteboard instead of the real clipboard),
  `ICONSMITH_TRASH_DIR` (replaced exports go there instead of the Trash),
  `ICONSMITH_APPEARANCE=light|dark`. Fixtures: `swift apps/Iconsmith/Tools/make-fixtures.swift`.

### Gates

- Unit tests: 60 (Swift Testing) + 1 opt-in volume test. Includes real `setIcon`
  round-trips (folder + file, apply → undo → remove → undo) and locked file / fake `.app` /
  missing item refusals, all under `/tmp/iconsmith-test/unit/`.
- Volume icons: APFS and FAT32 disk images created and mounted `-nobrowse` under
  `/tmp/iconsmith-test/`, `ICONSMITH_TEST_VOLUME=… swift test --filter volume`: apply writes
  `.VolumeIcon.icns`, remove clears it, on both. Images detached afterwards.
- `scripts/check.sh Iconsmith --perf`: all PASS. Launch 215 ms, first window 448 ms, idle
  CPU 0.019% (lowest window), footprint 37.9 MB empty; ~70 MB with a 1600×1000 photo loaded
  after cycling all shapes.
- Xcode: exported `AppIcon.appiconset` (macOS + iOS + watchOS) compiled with `xcrun actool`
  for macosx, iphoneos and watchos: no warnings or errors (a deliberately broken
  Contents.json does produce an error, so actool was really checking). iOS PNG has no alpha.
- Walkthrough on the release build with `scripts/drive` (light and dark): empty state,
  open via `open -a`, every shape, Fit/Fill, size (⌘=/⌘-), ⌥-arrow nudge, drag-to-move
  in the preview (mouse) + undo, ⌘0, Background Automatic/None/Color, tiny-picture warning,
  damaged file alert (Esc dismisses), SVG, an app as source (Calculator's icon), paste of
  JPEG data and of text-only (alert), ⌘C, every export format via File ▸ Export As
  (`iconutil -c iconset` round-trips the .icns; .ico has 7 images; favicons folder complete
  and HTML on the clipboard), the save panel's Replace prompt (old export went to the
  override trash), Apply by dragging folders and a text file from Finder onto the well
  (Finder shows the icons), Remove (incl. "No custom icon"), undo/redo of both, Settings
  (General + About). Screenshots: `/tmp/iconsmith-test/shots/`.
- `scripts/drive tree`: no `[unlabeled]` controls in the main window, Settings or sheets.
- Design checklist (§10): 1 pass (drop → icon → drop folders or ⌘E); 2 pass (system
  controls, accent colour, no hex, light/dark checked); 3 pass (every action in File / Edit
  / Icon menus with shortcuts); 4 pass (Esc closes alerts and panels, ⌘, Settings, ⌘Q,
  ⌘W); 5 pass (General: Show exported files in Finder; About. Launch at login dropped in round 1: not useful for a window app); 6 pass;
  7 pass (DropZone with symbol, one line, click to choose); 8 pass (no permissions needed);
  9 pass (every icon change undoable; replaced exports go to the Trash); 10 pass (no
  network code); 11 pass; 12 pass; 13 pass (no movement animations beyond SlopKit's
  DropZone, which honours Reduce Motion); 14 pass (single `Window` scene keeps its frame;
  shape/background/format remembered).

### Found and fixed during testing

- Save panel appended `.appiconset` twice (folder formats now don't set a content type;
  `ExportWriter` enforces extensions). A fresh save panel's "Untitled" name leaked into the
  suggested name. Opening a second panel from the menu while one was up: menu items now
  disable while a panel is showing.
- Exporting PNG next to `logo.png` offered to replace the source (now `logo Icon.png`).
- Bitmap readers assumed `width × 4` bytes per row; CoreGraphics pads rows (e.g. 100 px →
  448 bytes). All readers now use `bytesPerRow`.
- The Export button scrolled out of view at the default window size: Format + Export are
  now pinned under the inspector, options moved into the save panel.

### Risks / notes

- The save and open panels are out-of-process; `scripts/drive` can press their buttons but
  can't type into Go to Folder. Choosing targets in the ⌘J panel by automation is
  impractical; dragging from Finder (`--allow-over Finder`) works.
- Custom file icons add a resource fork (~170 KB per file with all sizes). Same as Finder's
  own Get Info paste.
- Folder art is measured from the current OS's folder icon; if a future macOS changes the
  folder shape a lot, `FolderLayout.standard` is the fallback.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Tester: all exports correct on disk; one major. Triage by the coordinator, fixed by the
builder. Gates re-run green: 63 unit tests (+1 opt-in volume test), `scripts/check.sh
Iconsmith --perf` (launch 136 ms, first window 282 ms, idle CPU 0.019%, footprint 39.7 MB),
walkthrough on the release build in light and dark through posted keys and Accessibility
only, no `[unlabeled]` controls.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Circle and Square did nothing visible for transparent pictures; thumbnails didn't look like their shapes; "Fill Shape" only in the Icon menu | major | accept | Automatic background now fills every outlined shape (edge colour, else white), so picking a shape always shows it. With Background None, the preview and the shape thumbnails draw the shape as a dashed outline; filled thumbnails get a hairline so a white tile reads on a light window. Fit/Fill is the "Framing" control in the Picture section and an Icon ▸ Framing submenu. Tests updated. |
| F2 Export As ⇧⌘3/4/5/6 clash with macOS screenshots | minor | accept | Export As is now ⌥⌘1–⌥⌘6. |
| F3 Favicons export replaced the clipboard | minor | accept | No clipboard write on export. The status line offers **Copy HTML**. `ICONSMITH_PASTEBOARD` lets scripted runs verify copying on a private pasteboard (verified: the three `<link>` tags). |
| F4 Long status message squeezed the inspector and clipped the Background caption | minor | accept | Status is one line ("Saved “name”", middle-truncated, path in the tooltip) with small buttons: export notes (popover), Copy HTML (favicons), Show in Finder. |
| F5 Undo didn't revert ⌘= / ⌥← steps; Undo disabled after one | minor | accept (investigated) | Cause: Undo went through the key window's responder chain, so keys posted to a background app (or with focus elsewhere) found no undo manager, while ⌘= and ⌥← (our own commands) still worked. Fix: the model owns its UndoManager and Undo/Redo are our commands with live titles ("Undo Move Picture"). Verified on the release build without activating it: ⌘=, ⌘=, ⌥←, ⌥← then ⌘Z ×4 steps back one at a time to 100% centered; ⇧⌘Z redoes. Logic moved to `ReversibleEdit` in the core with tests (4 steps undo one by one and redo; dropping editor steps keeps icon steps). |
| F6 "Fill" meant two things | nit | accept | Picture: "Framing: Fit / Fill". Background row is now "Background: Automatic / None / Color"; the menu item is Icon ▸ Framing ▸ Fit/Fill. |
| F7 App icon was a generic window glyph | nit | accept | Lucide `shapes` (triangle, square, circle: the shapes you pick from), in `Icon.svg`, `app.json` and the roadmap entry. |
| F8 manifest.webmanifest escaped slashes and lacked fields | nit | accept | `.withoutEscapingSlashes`; adds `name`, `short_name` (picture name), `theme_color` / `background_color` (the icon's background as #RRGGBB), `display: standalone`. Test added. |
| F9 Launch at login doesn't belong; Finder window per export | nit | accept | Settings is our own TabView (General + About) without Launch at login. Reveal already reuses a Finder window that shows the folder; the setting's caption says so. |
| Untested by the tester: applying icons by dragging from Finder | — | verified by builder | With the owner idle ≥ 60 s: dragged `targets/Project Alpha` from Finder onto Apply to Files & Folders → "Applied to 1 item", Finder custom-icon flag set; ⌘Z posted to the background app removed it. The ⌘J chooser now opens in `ICONSMITH_ALLOWED_ROOT`, but the out-of-process panel can't select items through Accessibility. Lesson for testers: `--allow-over Finder` also allows a *drop* on another Finder window covering the well (a first attempt moved the folder into an open "pictures" window, all inside /tmp/iconsmith-test; moved back). Check the drop point alone with `clickxy Iconsmith x y --allow-mouse --check` first. |
