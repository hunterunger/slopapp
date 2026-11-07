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
   supported yet." *(Superseded by the parity pass: built, behind a confirmation.)*
2. **Icon Composer `.icon` export**: later.
3. **Favicons and Windows .ico**: should, done (both shipped in v1).
4. **Android**: later. *(Parity pass: built.)*
5. **Background removal**: later. *(Parity pass: built with Vision.)*
6. **Text/emoji overlay**: skip (macOS 26 Finder's Customize Folder does it). *(Parity
   pass: built, incl. badges.)*
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

## Parity pass (2026-11-03)

Owner's direction (docs/parity-pass.md): look and work much more like the original, and
don't miss features. This section supersedes the "skip"/"later" calls above where they
conflict.

### How the original was studied this time

The installed Setapp build still stops at the Setapp licence check, so it wasn't launched
again (getting past it means touching the owner's Setapp login). Sources: the official
site's screenshots and copy (img2icnsapp.com: main window, export window, template
settings popover, batch counter, text/emoji, background removal, restore, folder colours),
the four Mac App Store screenshots, and the bundle's resource file names (read-only
listing: per-template `_back`/`_mask`/`_top` artwork for folders, documents, drives, discs,
cartridges…). Images were downloaded to `/tmp/iconsmith-parity/` and viewed there; none
were copied into the repo.

What the original looks like: a compact white window. Most of it is a **big round drop
canvas** (the picture, drawn in the current template, on a checkerboard), with a round
**back** button at its top left and a round **template settings** button at its top right.
Under the canvas, a one-line hint ("now drop a file or folder…") and two buttons: **Remove
Background** and **Export**. A **template column** runs down the **right** side (the
research above said left, from the interface files; the screenshots show it on the right):
each template is a large live preview of your picture with its name, the selected one
highlighted. Empty state: the canvas says "drop any image", and **Create / Restore** tabs
sit along the bottom edge. Export opens a window of format tiles (Folder, ICNS, iOS,
Android, Favicon, Iconset, ICO, PNG, JPEG) with per-format checklists. Template settings is
a popover: Horizontal Offset, Vertical Offset, Zoom, Rotation sliders, Background colour,
Reset All. Batch: a round counter with a menu of the loaded files.

### Gap table

| Item (original) | Before this pass | Now | Notes |
|---|---|---|---|
| Big canvas as the main element, round corner buttons (back, settings) | Preview left, inspector form right | **done** | Canvas with a close (×) button top-left and an Adjust button top-right, like theirs; our canvas is a rounded square (theirs is a circle on stripes / checkerboard: signature look, not copied). |
| Template column with live previews down the right side | 3-column shape grid in the inspector | **done** | `TemplateGallery`: two sections (App Icons, Folders & Files), 64 pt live previews with names; shows each template with a picture glyph before anything is loaded. |
| Create / Restore tabs along the bottom | Two drop wells at the bottom | **done** | Segmented control in a bottom bar (⌃⌘1/⌃⌘2). Restore is a big drop zone with per-item results. |
| Drop a folder/file on the canvas to apply | Separate "Apply" well | **done** | Same flow, **no timer**: files, folders, disks and apps dropped on the icon get it; pictures dropped there replace the picture (⌥-drop applies to pictures too). Hint line under the canvas + "Choose…" (⌘J). |
| Template settings popover (H/V offset, zoom, rotation, background, Reset All) | Size slider, Fit/Fill, background in the inspector | **done** | Adjust popover: Size, Horizontal, Vertical, **Rotation** (new), each with value + per-row reset; Framing Fit/Fill; Background or Folder Color with 11 system-colour swatches + colour panel; Reset All. ⌘[ / ⌘] rotate 90°. |
| Export window of format tiles with per-format options | Format popup + save-panel accessory | **done** | Export popover: 3×3 tiles (Folder, ICNS, Xcode, Android, Favicon, Iconset, ICO, PNG, JPEG), the chosen format's options and description, Export…. ⌘E still exports the last format directly; the save panel keeps its accessory. |
| Folder templates: full, centred, engraved, dark variants | One Folder shape | **done** | Folder (centred), **Folder Cover** (full front), **Folder Symbol** (engraved: the picture's silhouette pressed into the folder in a darker tone, white details become holes), all composed on the live system folder. Dark folders = the folder colour (black/grey swatch). |
| Folder colours | — | **done** | Folder Color recolours the system folder keeping its shading (grey × colour, colour-dodge for bright tints); symbols and text follow it. |
| Document template | — | **done** | On the live blank-document icon. |
| iOS-style rounded template | — | **done** | "Rounded": full-canvas continuous corners. |
| Text / emoji (typeface, weight, size, colour, alignment) | skip | **done** | Text popover: text/emoji field + Emoji & Symbols button, Position (Middle/Top/Bottom/**Badge**), Font (System/Rounded/Serif/Monospaced), Weight, Fit Automatically or manual size, Automatic/Custom colour, badge colour, Remove Text. Top/Bottom labels shrink the picture away from the text. Folder text is pressed in like a symbol. |
| Use Blank Image | — | **done** | File ▸ New Blank Icon (⌘N) and a button on the empty state. |
| Remove background (colour-pick lens + tolerance) | later | **done (better)** | Vision subject lifting (`VNGenerateForegroundInstanceMaskRequest`, on device), one button; Restore Background / ⌘Z. Clear message when there's no subject. |
| Batch: many images, counter + menu, export all | later | **done** | Drop/open several; toolbar "1 of N" menu, ⌥⌘←/→; Export popover "All N pictures, into one folder" (⇧⌘E) writes one output per picture with collision-free names. Same template/colour/text for all. |
| Export: Android | later | **done** | `res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher(.png,_round,_foreground,_background)`, `mipmap-anydpi-v26` adaptive XML (+ monochrome for logos), 512 px Play Store icon. |
| Export: iOS dark / tinted | later | **done** | Xcode option "iOS dark and tinted icons": dark = picture on transparency, tinted = greyscale on black, `appearances: luminosity` entries. `actool` (iphoneos 18, macosx) compiles it with no warnings. |
| Export: Folder | skip | **done** | A new folder carrying the icon (through the same applier, so it respects `ICONSMITH_ALLOWED_ROOT`). |
| Export: JPEG | skip | **done** | On white, PNG sizes; notes when transparency became white. |
| Export: ICNS, Iconset, ICO, PNG, Favicon | done | done | Unchanged (modern sets). |
| Drag the result out | later | **done** | Drag any of the small sizes to Finder: `.icns` (⌥: PNG), written at drag start. |
| Icon for `.app` bundles | refused | **done (careful)** | Apps dropped or chosen ask first (Change Icon / Use Its Icon as the Picture / Cancel) and explain that updates reset it. Apple's apps (system volume) and admin-owned apps are refused with a reason before anything is touched; a macOS refusal shows "Allow Iconsmith in Privacy & Security ▸ App Management" with an **Open Settings** button. Undoable. Tested only on our own stand-in `Fake Tool.app` under /tmp/iconsmith-test. |
| Restore mode | done (well) | done (tab) | — |
| Shortcuts actions (Set icon, Restore, Open with file) | later | **deferred** | ~0.5–1 day: App Intents in a SwiftPM-built app need an `AppShortcutsProvider` and metadata processing that our scripts don't run yet; needs a pipeline check first. |
| Novelty templates (CD/DVD/Blu-ray, vinyl, floppy, cartridges, Polaroid, stamp, film, booklet, drive, USB, SD…) | skip | **deferred / skip** | They're the original's bundled artwork (signature, not copyable). Drawing our own: ~1–2 h each; a generic photo frame and stack are the only ones with everyday value. Drive/USB could use the system's own drive icons (~1 h). |
| iOS legacy per-size sets, "rounded" iOS/Android option | — | **skip** | Xcode 14+ wants one 1024 px icon and masks it itself; pre-rounding causes double corners. The Rounded template covers the look. |
| Share button | later | **skip** | Drag-out, Export and ⌘C cover it. |
| Icon Composer `.icon` export | later | **deferred** | ~0.5 day; format undocumented and changing. |
| Finder Quick Action | later | **deferred** | Needs an app extension target, which the SwiftPM-only pipeline can't build yet (~1 day incl. tooling). |
| Localization (9 languages) | later | **deferred** | Strings are plain; needs String Catalog support in the pipeline. |
| Help menu how-tos, x-callback URL scheme, upsell/rating | — | **skip** | Help points to the README; no URL scheme (App Intents later); no upsells. |

### Deviations from the design system (and why)

- **Custom-drawn gallery cells and round corner buttons on the canvas** instead of stock
  controls: that's the original's layout (template column, back/settings buttons on the
  canvas). Built from SF Symbols, materials and the accent colour; labelled for VoiceOver.
- **Popovers instead of an inspector** for Adjust, Text and Export, because that's where the
  original keeps them. All three are also reachable from the menu bar with shortcuts.
- **Create / Restore tabs as a segmented control in a bottom bar**, matching the original's
  bottom tabs rather than a toolbar control.
- **Colour swatches and the badge's default red** are icon *content* colours (written into
  exports), not UI colours; the UI itself still uses only system colours.
- Not copied: the circular striped/checkerboard canvas, the dark teal template column, the
  Avenir type, their bundled template artwork, names and wording.

### Builder decisions (parity pass)

- **Gallery on the right**, as the screenshots show, though the interface files suggested left.
- **Canvas drop rules**: pictures replace the picture (as dropping onto the original's canvas
  before its timer does), everything else gets the icon; ⌥ forces "apply". Removes the
  original's timing problem while keeping its one-target flow.
- **Apps always confirm**, even from the chooser: the change lives inside someone else's
  bundle and updates undo it. The drop variant also offers "Use Its Icon as the Picture",
  because dropping an app to grab its icon is the other common intent.
- **Folder colour = the background setting** for folder templates (as in the original's
  template settings); Automatic/None mean the standard folder.
- **Batch keeps one template** for all pictures and resets only placement when switching.
- **Small previews are 64/32/16 pt** (were 128/32/16): the big canvas already shows the
  large size, and the shorter row leaves room for the hint and buttons.
- **Text autosize** fits the line into its area; manual size is a fraction of the
  template's text area so it means the same on every template.
- **Test hook** `ICONSMITH_DEBUG_DIR` (DebugHarness.swift): commands over a distributed
  notification + PNG renders of Iconsmith's own windows. Added because the Mac's screen was
  locked for this whole session, which hides windows from Accessibility and screen capture.
  Off unless the env var is set; renders only our windows.

### Gates (parity pass)

- Unit tests: **86** (Swift Testing; +23 this pass: every template renders, rounded
  corners, folder colour, folder symbol (alpha and ink masks), document placement,
  rotation, blank + text, text autosize/manual size, badge position/colour, automatic text
  colours, cut-out with a fake remover + no-subject + vector sources, Android plan and
  nested write, iOS dark/tinted (alpha, greyscale, JSON), JPEG, Folder export, batch
  naming, older ExportOptions decoding, colour maths, App Management hint, own `.app`
  bundle round-trip, Apple app detection) + 2 opt-in (volume icons, contact sheet).
- `scripts/check.sh Iconsmith --perf`: all PASS (final run: launch 152 ms, first window
  316 ms, idle CPU 0.021% lowest window, footprint 46.6 MB; earlier run 141/292 ms,
  0.011%, 46.8 MB).
- `actool`: an exported AppIcon with macOS + iOS + watchOS + dark/tinted compiles for
  iphoneos (18.0) and macosx with no warnings or errors.
- Real effects, all under /tmp/iconsmith-test via the debug hook on the release build
  (`ICONSMITH_ALLOWED_ROOT=/tmp/iconsmith-test`): every export format written and
  checked (`iconutil` round-trip, Android tree, JPEG opaque, Folder export has `Icon\r` +
  FinderInfo); canvas drop applied to 2 folders, the app confirmation alert shown, then
  `Fake Tool.app` got `Icon\r`, undo removed it, redo put it back; Restore removed all
  three; batch of 4 exported (`logo.icns`, `logo 2.icns`, …); Vision removed the
  background of `subject.jpg` and reported "no subject" on the synthetic landscape.
- Screenshots (offscreen renders of our windows, light + dark), all looked at: see below.
- Walkthrough with `scripts/drive`, `drive tree` for `[unlabeled]`, and the drag-out /
  Finder drop with the real mouse: **not run (screen locked)**, see "Walkthrough status".

Screenshots: `/tmp/iconsmith-test/parity/`, `light-*` and `dark-*` (offscreen renders of
Iconsmith's own windows by the debug hook; `-main` is the window, `-1`/`-2` the popover or
alert): 01 empty (gallery shows each template with a picture glyph), 02 logo, 03 Adjust
popover, 04 Text popover, 05 Export popover, 06 Folder Symbol + orange folder + "Design"
label, 07 batch "1 of 3" + Folder Cover, 08 blank folder with "LOL 😆", 09 Restore tab +
results, 10 badge, 11 background removed, 12 app confirmation, 13 app applied;
`light-14-no-subject-alert.png`. Replay: `/tmp/iconsmith-test/tools/walk.sh light|dark`.
Originals for comparison: `/tmp/iconsmith-parity/` (not committed).

#### Walkthrough status

- **Not run this pass: `scripts/drive` walkthrough, `drive tree` `[unlabeled]` scan, and the
  real-mouse drags** (drag a small icon to Finder; drag a folder from Finder onto the
  canvas). The Mac's screen was locked for the whole session (HID idle > 30 min,
  `loginwindow` frontmost), and macOS hides every window from Accessibility and screen
  capture while locked, so SlopDrive can't see or drive the app. Nobody was there to unlock
  it, and unlocking it isn't ours to do. Waited 30 more minutes for an unlock; none came.
- What stands in for now: the same flows driven through the debug hook on the release
  build with real effects checked on disk (above), offscreen renders of every state in
  light and dark, and a label audit by reading the code. Every new control has an
  accessible name: corner buttons ("Close Image", "Adjust"), template cells (template
  name + selected trait), format tiles (format title + selected), swatches (colour
  names), slider rows (title, value, "Reset …"), Emoji & Symbols, the batch menu
  ("Pictures", "n of N"), small previews ("Preview at n points" + drag hint), the mode
  picker ("Mode").
- To do on the next unlocked run (blind tester or builder): `scripts/drive tree Iconsmith`
  in each state (empty, loaded, each popover, Restore, the app alert); drag `targets/Project
  Alpha` from Finder onto the canvas (owner-away rule, `--allow-over Finder`); drag the
  64 pt preview into a Finder window showing `/tmp/iconsmith-test/exports` (expect
  `logo.icns`; with ⌥, `logo.png`). The drag file is written at drag start (≈60 ms for an
  .icns, release).

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

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md` ("a very close attention to detail"). Finish only, no new
features. Release build stamped with SDK 27.0 (full-size 16×16 window buttons, current
controls). Every surface shot with `scripts/drive shot` in light and dark
(`SLOP_APPEARANCE`), state driven through the debug hook, popovers also rendered in-process
for exact geometry; all measured with `scripts/measure` (pixel probes at `--scale 1` for
hairlines). Test data only under `/tmp/iconsmith-test/`.

### Defects found and fixed (before → after)

| # | Where | Before | After |
|---|---|---|---|
| 1 | Lint | 8 corner-radius literals (canvas 16, format tiles 8, gallery cells 10), 1 spacing literal (swatches 6) | 0 / 0: `Radius.xxl` canvas, `Radius.l` tiles, gallery ring derived from each template's outline, swatch spacing `Spacing.s` |
| 2 | Separators | 3 SwiftUI `Divider`s in the window + 1 in Export: 1 pt (2 px `#EAEAEA`) | `Hairline()`: 0.5 pt (1 px), measured |
| 3 | Canvas corner buttons | 30 pt circles (r 15) 8 pt inside a 16 pt canvas: not concentric (needs r 8) | 28 pt circles (r 14) 8 pt inside a 22 pt canvas (22 − 8 = 14); measured inset 8.0 pt on both axes, 28 pt wide |
| 4 | Canvas states | 1 pt `primary` 8 % border; drop target 2 pt *dashed* accent; focus = 1 pt accent 50 % border, shown after every popover closed | 0.5 pt separator hairline; drop target solid 2 pt accent + 10 % tint (as SlopKit `DropZone`); system focus ring (3 pt, follows the corners) only with Keyboard navigation on, like Preview's image view |
| 5 | Empty → loaded | Drop zone 438 × 438 at y 117, radius 12; canvas 411 at y 72, radius 16: the box jumped and changed corners on load | One square slot for both, radius 22, controls under it reserved in both states: 0 pt shift (366 pt square at y 72 in both at the default size) |
| 6 | Export result | "Saved …" line appeared under the buttons and pushed the canvas up | Moved to the leading end of the bottom bar (status-bar style), middle-truncated, 20 pt icon targets: 0 pt shift |
| 7 | Action row alignment | 440 pt wide under a 411 pt canvas (14.5 pt past each edge) | Exactly the canvas width (366 = 366); when the canvas is narrower than the buttons (min window), they overhang it evenly, never truncate |
| 8 | Action row heights | Text 28 pt, Remove Background 29 pt, Export 29 pt (symbol baselines) | All 29 pt (fixed label height) |
| 9 | Gallery selection | 1.5 pt accent ring around the whole 144 × 99 cell at radius 10, unrelated to the 64 pt tile; label tinted accent | Ring 2.5 pt outside each template's own outline and 2.5 pt wide: concentric with the macOS superellipse, the circle, the square (true arcs), an icon-tile square for templates without an outline. Label in a Finder-style accent pill. Hover ring. Geometry in `TemplateRingGeometry` with a test |
| 10 | Gallery scrolling | ⌘1–⌘9 / Icon menu could pick a template that stayed off-screen | Scrolls it to the centre (snappy, Reduce Motion: no animation); clicks don't scroll |
| 11 | Gallery under toolbar | Scrolled content drew into the toolbar strip (faint "App Icons" at y ≈ 41 pt, above the column); dark strip over the column lighter (`#323435` vs `#2B2E2E`, macOS 26 scroll edge effect) | Clipped at the column; edge effect hidden: strip `#292A2A` = column |
| 12 | Results list | "Icon applied"/"Restored" plain green ≈ 2.0 : 1 on white; failures plain orange; "⌘Z to undo" in `.tertiary`, and shown after "No custom icons removed" (nothing to undo); icon buttons 12 × 13 / 13 × 13 pt targets; 16 pt side padding | `.textGreen` ≈ 3.9 : 1 on the anti-aliased caption glyph, `.textOrange`; hint `.secondary` and only when something changed; 20 × 20 targets; 20 pt (window margin) |
| 13 | Restore tab | Drop zone 518 × 438, radius 12 | Same square slot and 22 pt radius as Create's |
| 14 | Bottom bar | Vertical padding 10 (s + 2); tabs in a 300 pt frame drawn 149 pt wide | 12 pt; natural width, centred by equal flexible sides |
| 15 | Adjust popover | "Background" header *and* "Background" picker (folders: "Folder Color" twice); caption a separate row, 1–2 lines depending on mode; colour well row only in Color mode (popover grew 45 pt); swatches had no selected, hover or pressed state | One label; caption is the picker's one-line subtitle in every mode; "Custom Color" well always there (no resize); chosen swatch gets a 2 pt accent ring 1.5 pt outside (no layout change), hover darkens its hairline, press scales to 92 % |
| 16 | Popover footers | Reset All / Remove Text / Done at 16 pt from the sides while sections sit at 10 pt (6 pt off); 18 pt above vs 10 pt below | 10 / 10 / 10, edges flush with the sections (measured) |
| 17 | Popover widths | 340 / 340 / 360 | 360 for all three |
| 18 | Export popover | Changed height per format (options 0 → ~70 pt for Xcode), so Export… moved; tiles had no hover/pressed state | Options area reserved at the tallest format; `TileStyle` hover (7 %) and pressed (12 %) fills |
| 19 | Text popover | Position segmented wrapped and floated with a 56 pt hole on the left | Label above, control leading-aligned under it |
| 20 | Drag-out handles | 64/32/16 pt previews: tooltip only | Hover highlight (`Radius.m`, 4 pt outset, no layout change) + open-hand cursor |
| 21 | Round buttons | No hover or pressed state; 1 pt 12 % stroke | 8 % / 16 % overlays; hairline border |
| 22 | Transparency | None shown: transparent margins looked like canvas, a white Circle/Square tile was barely visible on the light canvas | Subtle 8 pt checkerboard behind the icon's own square (= the exported image's extent, whole cells only); dashed guide kept for Background None, its tint dropped |
| 23 | Background removal | Bare large spinner | "Removing Background…" capsule with a small spinner (fades in) |
| 24 | Settings | Explanation as its own row, 2 lines | Subtitle under the toggle, one line |
| 25 | Batch counter | "n of N" proportional digits | `.monospacedDigit()` |

Also checked and fine: macOS App shadow (10 px offset, 24 px blur, 30 % black at 1024,
same as `scripts/icongen.swift`; Apple-template reconstructions range 10–12 px / 10–28 px /
30–50 %, so kept so Slopapp's own icons match), Apple grid tile (824/1024), alerts (system),
About (SlopKit), minimum window size 700 × 640 with a 90-character file name, 6 results,
and a favicon export status (middle truncation, nothing overlaps).

Decisions: the checkerboard is the generic transparency grid, limited to the icon's square;
the original's whole-canvas circular checkerboard isn't copied. The results panel still
shrinks the canvas when it appears (≈ 110 pt for 3 rows): a panel the user caused, and
overlaying it would cover the gallery and the canvas.

### Gates

- `scripts/lint.sh Iconsmith`: pass (was 8 failures + 1 warning).
- `scripts/check.sh Iconsmith --perf`: all PASS. 88 tests (+2: swatch matching, ring
  concentricity on every template). Final run: launch 166 ms, first window 335 ms, idle CPU
  0.042 % (lowest window), footprint 50.9 MB (parity pass: 152 / 316 ms, 0.021 %, 46.6 MB).
- `scripts/drive tree`: no `[unlabeled]` in the window (empty, loaded, batch, results,
  status), the three popovers, the app alert or Settings. Window buttons 16 × 16.

### Screenshots

`/tmp/slopapp-polish/iconsmith/`: `before-light/`, `before-dark/` (start of the pass),
`after-light/`, `after-dark/` (final build: 01 empty, 02 logo, 03 every template, 04
Background None, 05 Adjust (app, colour, folder), 06 Text (+ badge), 07 Export (ICNS,
Folder, Xcode, PNG), 08 export HUD + status, 09 results, 10 app alert, 11 batch (+ export),
12 blank folder with text, 13 background removed, 14 error alert, 15 Restore (+ results),
16 Settings; popovers rendered in-process in `dbg/after-*`), `r5-dark/16-settings-general.png`,
`edge/` (minimum window size, long name, 6 results), `dbg/cutout-progress*-main.png`.
Walkthrough: `/tmp/slopapp-polish/iconsmith/tools/walk.sh light|dark <prefix>`.

### Not done, and why

- **Hover with the real pointer** (gallery cells, swatches, tiles, round buttons, small
  previews) and the **real-mouse drags** (drag-out to Finder, Finder drop on the canvas):
  not observed. The owner was at the Mac the whole pass (HID idle 2–11 s), so no real-cursor
  actions. All hover states are designed in code.
- **The save panel's accessory** wasn't re-shot (out-of-process panel).
- **Background-removal progress** shows for under 120 ms on this Mac (Vision); the result
  state was checked, the overlay itself barely appears in a render.
- Test-only debug hook commands added: `reveal:on|off`, `swatch:<name>`, `winsize:<w>,<h>`.
  The walkthrough resets `app.slopapp.iconsmith` preferences (the parity script did too);
  the key was deleted at the end so the app starts from defaults.

### Golden Gate + light/dark (2026-11-06)

Owner: "ensure all the apps are optimized for dark/light mode AND look like they fit in with
macOS Golden Gate" (this Mac: macOS 27.2). Checked against design system §4 "Fitting in on
macOS 27 Golden Gate" and §10 items 25–26, on the release build, every surface in light and
dark side by side, plus inactive-window shots and a live appearance switch.

| Check | Before | After |
|---|---|---|
| Menus text-only | Menu bar commands and the batch menu were already plain text; the Create/Restore segments carried symbols (hidden, but in the AX tree) | Segments are `Text` only. Symbols stay only in toolbar items (standard) |
| Toolbar | Real `.toolbar` (Open Image, batch menu), system glass | Unchanged: standard |
| Inactive window | Gallery ring + label pill, swatch ring, format tiles stayed accent blue when the window wasn't key, while the system's own Export button and tabs went grey | `Color.selectionRing` / `.selectionFill` / `.selectionTint` / `.windowAccent` on `controlActiveState`: all grey together (label text switches to `.primary` on the grey pill). Drop-target accent kept (it shows during a drag from Finder, when Finder is key) |
| Glass | `.regularMaterial` on the round buttons and the background-removal capsule; system popovers | Unchanged: system only |
| `.secondary` as the only copy | "No custom icon" (a row's outcome) in `.secondary`, ≈ 3.1 : 1 in light on 27.2 | `.primary`; `.secondary` left only on supporting text (hints, captions, sizes) |
| Drawn pure white / black | Gallery placeholders (before a picture): glyph in `secondaryLabelColor`, drawn off the main thread, came out light grey in dark mode and vanished on the white Automatic tile, leaving blank white squares | Glyph in `systemGray`, reads on the white tile and on clear templates in both modes. White/black swatches are icon colours (data) with a `primary` 20 % hairline |
| Chrome around previews | Canvas fill, checkerboard, guide, thumbnail outlines are `primary` opacities; tile shadow is part of the exported icon (data) | Verified in both modes; nothing fixed-grey |
| Live appearance change | — | Launched light, switched to dark while running (and the reverse): canvas fill, both checker tones, gallery, bottom bar and hairline pixels identical to a dark (light) launch |
| Hairlines (SlopKit `Hairline` now lays out 1 pt) | Bottom bar 12.5 pt above the tabs / 12 below; results list 8.5 / 8; export popover divider 12 / 12.5 | Content under a hairline gives back the unused half point (`HairlineGap`): 12 / 12, 8 / 8, 12 / 12 (pixel-measured, light and dark) |
| DropZone (SlopKit update) | — | Empty Create and Restore zones re-shot both modes: radius 22 via `.dropZoneCornerRadius`, same square slot as the canvas, dashed outline readable in dark |

Gates: `scripts/check.sh Iconsmith --perf` all PASS (88 tests; launch 154 ms, first window
343 ms, idle CPU 0.015 %, footprint 51.8 MB). No `[unlabeled]` in any state. Lint clean.

Screenshots (`/tmp/slopapp-polish/iconsmith/`): `final-light/`, `final-dark/` (every surface,
same numbering as the polish pass), `final-gg-light/`, `final-gg-dark/` (01 active, 02
inactive main window with Settings in front, 03 Restore, 04 live switch to the other mode),
popover renders `dbg/final-*` and `dbg/final-gg-*-export-active-1.png` (popover in an
active app: accent selection).

**Idea, not built: Golden Gate icon looks.** Golden Gate shows app icons as Default, Dark,
Clear and Tinted, and generates those looks itself for icons that only ship a single image
(our `.icns` / iconset / Xcode macOS sizes). A natural fit: a "Look" control under the small
previews (Default · Dark · Clear · Tinted) that previews roughly how the system will show
the icon (~0.5 day; approximate, Apple's derivation isn't public), and later an Icon Composer
`.icon` export with a real dark variant (~1 day, format undocumented; already deferred
above). Waiting for the coordinator's call.

Not done: real-pointer hover and drags (owner present). The owner's `app.slopapp.iconsmith`
defaults were backed up before the first launch and restored exactly at the end (verified
by diff); the owner's copy wasn't running.
