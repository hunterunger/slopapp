# Convert research (inspired by Permute)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Permute 4.1 (4173)**, Setapp build, at /Applications/Setapp/Permute.app
> (read-only), plus its built-in help (bundled as JSON in the app), its website, App Store and
> Setapp reviews. We study how it works so we don't reinvent the wheel. We never copy its
> name, icons, artwork, wording, sounds or signature visuals.
>
> Permute wasn't running. It was launched, walked through (menus, every Settings pane, every
> preset's options, the Add Preset sheet, which was cancelled) and quit. No setting was
> changed and nothing was converted. A synthetic test clip (generated, no personal content) was
> added twice through File > Open… to see the populated queue, but both times Permute
> stayed on "Loading…" and never showed it. After quitting and relaunching, the queue was
> empty. The populated-queue layout below comes from the demo screenshots in Permute's
> bundled help (demo files, not the owner's). Settings values are the values seen on this
> Mac. They look like factory defaults but may not be.
>
> Platform facts were checked with small Swift experiments on this Mac (**macOS 27.2, M4
> Max**), which is newer than our **macOS 14** floor. Anything only seen on 27 is marked
> "verify on 14". Experiment sources are in `/tmp/convert-exp/scripts` and are not in the repo.

## The job

Someone has a media file in the wrong format for where it needs to go. Examples: a screen
recording `.mov` that a website, Slack or a Windows colleague wants as `.mp4`; an iPhone HEIC
that a form wants as JPEG; a video whose audio should become a podcast-ready `.m4a`; a clip
that should be a GIF for a README; a folder of WAVs from a recorder that should be AAC. They
don't want to learn codecs, open a video editor or upload to a sketchy website. "Done" means
a new file next to the original, in the right format, playable everywhere, with the original
untouched. **The one interaction that matters: drop files → the format is already right (or
one click to change it) → new files appear next to the originals with a Show in Finder
button.**

## Who and when

- Turning a screen recording (`.mov`, often huge ProRes or HEVC) into a small, compatible MP4
  to share or upload.
- Turning an iPhone HEIC photo or HEVC video into JPEG / H.264 for someone on an older device
  or a picky web form.
- Pulling the audio out of a video (lecture, interview, music video) as M4A or WAV.
- Making a GIF from a short clip for docs, chat or a bug report.
- Batch-normalizing a folder of audio (WAV/AIFF/FLAC → AAC, or the reverse for an editor).
- Downie users: Permute is the post-processing step after a download (`permute://` URL hook).

Frequency: a few times a week in bursts, sometimes a big batch once a month. Each use lasts
10 s of interaction plus however long the encode takes (seconds for images, minutes for long
videos). People pick a format and rarely touch quality settings.

## How Permute is laid out

- **Main window** (about 1556×696 here, resizable). Empty state: a big round "+" button
  centred with a one-line prompt under it, and a bottom status bar with "+", a centred count
  ("No Conversions" / "3 Conversions") and a support button. Files can come from the + button,
  ⌘O, the status-bar +, a drop on the window or Dock icon, **⌘V paste of files**, a Finder
  Service ("Add Selected File to Permute"), the `permute://` URL scheme, a Shortcuts action, or
  a Drop Zone.
- **Queue = groups of cards.** Files are sorted into **groups by kind** (Images, Video,
  Audio…), automatically or by hand. Each group header (a tinted capsule) has: Start ▷, a
  **preset popup** (the target format for the whole group), name + "N files", "+" add to
  group, an options popover, a clear menu and a collapse toggle. Under it, each file is a
  wide **card with its thumbnail/frame as the background** and a dark gradient. The card shows
  the name, then an info line: images "355 KB · 960×720 · JPG", videos "1280×720 · H.264 ·
  7001 kbps · 41.27 fps · AAC · 49 kbps · Mono · 33.9 MB". It has a remove ⊗ and a bottom
  toolbar: Start ▷ and per-kind tools (images: colour picker for colour replacement, crop,
  options; videos: crop, trim, audio tracks, subtitles, options).
- **Nothing starts until you press Start** (group, file, status bar, or File > Start
  Conversions ⌘S). The exceptions are Drop Zones and, if enabled, automation sources.
- **Group options popover**: Destination (Default / folder), Transformation (rotate/flip),
  Resize, File Size Restriction, plus per-context items (stitch, bitrates, volume, speed).
  At the bottom: "Load From…" (apply a Custom Group), sort by name, and Schedule Start.
- **Trim sheet**: a preview with a time readout, a range slider with in/out handles, and
  nudge buttons each side (±10 s, ±5 s, frame/large steps, ±0.1 s). There's an actions menu
  (apply to whole group, saved values), plus Cancel / Done. Audio shows a waveform.
- **Settings**: sidebar window (880×682) with 8 panes, a toolbar search field, and a
  three-column Presets pane (preset list with enable checkboxes and a "⋯" menu per preset →
  grouped form of options).
- **Drop Zones**: a floating window of coloured tiles. Each tile is bound to one or more
  presets or a custom group. Dropping on a tile converts immediately with no questions.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason). "Apple-only?" says whether AVFoundation / ImageIO /
AudioToolbox can do it on macOS 14+ (✅ verified by experiment, ⚠️ verify on 14 / partial,
❌ not possible without a third-party codec).

### Getting files in

| # | Feature | How Permute does it | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|---|
| 1 | Drop files/folders on the window | Drop anywhere; folders searched recursively (setting on) | ✅ | must | FileQueue already does this (`FileIntake`, 5,000-file cap, hidden files skipped). |
| 2 | Choose Files… (⌘O) | Big + button, File > Open…, status-bar + | ✅ | must | `FileQueueActions.chooseFiles`; DropZone click. |
| 3 | Drop on Dock icon / Open With | Dock drop adds files | ✅ | should | `CFBundleDocumentTypes` for `public.movie`, `public.audio`, `public.image` as Viewer/Alternate so we never steal defaults. |
| 4 | Paste files (⌘V) | Pastes file URLs from the clipboard into the queue | ✅ | should | Cheap: read `NSPasteboard` file URLs on ⌘V. |
| 5 | Finder Service "add to app" | `NSServices` entry for selected files | ✅ | later | Finder Quick Action / Service "Convert with Convert". |
| 6 | Custom drop ("drop here to customize") | Bubble while dragging; drop on it to review files and pick a group (Automatic / existing / custom / new) | ✅ | skip | Extra step; our per-kind targets make it unnecessary. |
| 7 | Auto-detect external subtitles (`Video.srt`, `Video [eng].srt`) | On by default, with language detection, default encoding | ⚠️ (AVFoundation can mux tx3g/WebVTT, not trivial) | skip | Niche; out of scope for a drop-and-done app. |

### The queue

| # | Feature | How Permute does it | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|---|
| 8 | Queue list with per-file progress | Cards in groups; progress on each card; status bar count | ✅ | must | FileQueueView rows: thumbnail, name, before → after, progress, Cancel / Try Again / Show in Finder. |
| 9 | Group files by kind, one target per kind | Automatic groups (Images, Video, Audio…); each group has its own preset popup | ✅ | must | **Our version: one target format per kind** (Video / Audio / Image) in the bottom bar, no groups UI. A mixed drop just works: each file uses its kind's target. |
| 10 | Manual start (▷ per file / group / all, ⌘S) | Nothing runs until Start | ✅ | — | **We start on drop** (design system: one drop, no setup). Changing a target doesn't touch finished rows; "Convert Again" re-runs them. Open question 3. |
| 11 | Media info on each item | Size · dimensions · codec · bitrate · fps · audio codec · channels | ✅ (`AVAsset.load`, `CGImageSource` properties) | should | Waiting/done row detail like "1920×1080 · HEVC · 2:14". Needs a FileQueue row-detail hook (see FileQueue gaps). |
| 12 | Cancel / remove a file, clear finished (⌘K), Pause All (⌘P) | Per-card ⊗, group clear menu, File menu | ✅ | must (cancel, clear) / later (pause) | FileQueue has cancel, cancelAll, remove, clearFinished. No pause; cancel + Try Again covers it. |
| 13 | Concurrency limit, Low power mode | Setting: Default (auto) or a number; low power = 1 at a time, fewer cores | ✅ | must (sane default) / skip (setting) | Video encode should run **1–2 at a time** (media engines); images can run wide. FileQueue has one `maxConcurrent` (see gaps). |
| 14 | Schedule Start (⇧⌘S) | Start group or queue at a time | ✅ | skip | Niche; macOS users can just drop later. |
| 15 | Show result | Reveal in Finder after finishing; double-click | ✅ | must | FileQueue row button + double-click/Return. Add Space = Quick Look the output (should). |
| 16 | Thumbnails | Setting "Enable Thumbnail Generation" (on) | ✅ | must | FileQueue's lazy QuickLook thumbnails (already). No setting needed. |
| 17 | Persist queue across launches | Not observed (queue was empty after relaunch) | — | skip | Same as Squish: the list is per session. |

### Output formats: video

| # | Permute preset / output | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|
| 18 | **MP4 (H.264 + AAC)** | ✅ AVAssetWriter `.h264` or export presets | **must** | The default video target. Plays everywhere. |
| 19 | **HEVC (H.265) in MP4/MOV** | ✅ `.hevc` (hardware on Apple silicon; Intel Macs from 2017) | **must** | Tag `hvc1` so QuickTime/iOS play it (AVFoundation does this by default). |
| 20 | HEVC with alpha | ✅ `.hevcWithAlpha`, `AVAssetExportPresetHEVCHighestQualityWithAlpha` | later | For transparent ProRes 4444 sources. |
| 21 | ProRes 422 / 4444 (MOV, PCM audio) | ✅ (export presets `AppleProRes422LPCM` / `4444LPCM`; VT has HW + SW ProRes encoders) | should | For editors. 3 s 720p clip → 27 MB, so warn nobody; it's what they asked for. |
| 22 | Device presets (iPhone, iPad, Apple TV, Plex, Roku, Xbox) | ✅ for Apple ones (H.264/HEVC at capped sizes) | skip | Today every device plays H.264/HEVC MP4. Resize covers the rest. |
| 23 | "Small File" / "High Quality" MP4 presets | ✅ via `AVVideoQualityKey` / bitrate on AVAssetWriter | **must (as a Quality control)** | Our Quality popup: Smaller / Balanced / Best. See key finding below. |
| 24 | **GIF animation** (video → GIF, loops forever) | ✅ `AVAssetImageGenerator`/`AVAssetReader` frames → `CGImageDestination` GIF (3 s → 480 px, 10 fps: 0.6 MB in 0.37 s) | **must** | Defaults: 10–15 fps, max width 480–640, loop forever. ImageIO's palette is basic; acceptable for v1. Cap duration (warn above ~30 s). |
| 25 | APNG / WebP animation / AVIF animation | APNG ✅ (ImageIO PNG with APNG delay keys); WebP ❌; AVIF anim ⚠️ | later (APNG) / skip | |
| 26 | Video to Images (frame every N s, JPEG/PNG…) | ✅ | later | Produces many outputs per input; FileOutcome supports one output URL (gap). |
| 27 | AV1 | ❌ no encoder in VideoToolbox (decode only, hardware-dependent) | skip | List under "can't". |
| 28 | WebM (VP8/VP9), MKV, AVI, DivX/Xvid, WMV, FLV, MPEG-1/2, Ogg Theora, DNxHD, HAP, HLS, MP4 (MPEG-4 Part 2) | ❌ no muxers/encoders (AVAssetWriter writes only MOV, MP4, M4V, M4A, 3GP/3G2, CAF, WAV, AIFF/AIFC, AMR, caption formats) | skip | FFmpeg territory. Say so plainly in the README. |
| 29 | Color Replacement (chroma-key to ProRes 4444) | ✅ (Core Image + ProRes 4444) | skip | Editing, not converting. |
| 30 | Advanced Custom (raw FFmpeg arguments) / Custom (container+codec matrix) | ❌ / ✅ | skip | Power-user escape hatch, the opposite of our audience. |

### Output formats: audio

| # | Permute preset / output | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|
| 31 | **M4A / AAC** | ✅ `AVAssetExportPresetAppleM4A` or AVAssetWriter AAC | **must** | Default audio target, also "extract audio from video". |
| 32 | **MP3** | ❌ **no MP3 encoder in macOS** (`kAudioFormatProperty_EncodeFormatIDs` lacks `.mp3`; ExtAudioFile and AVAssetWriter both refuse). Decoding works. | **can't** | In the roadmap spec, but impossible Apple-only. Open question 1. |
| 33 | **WAV** (16/24-bit PCM) | ✅ AVAssetWriter `.wav` LPCM or ExtAudioFile `WAVE` | **must** | |
| 34 | AIFF | ✅ | should | Same code path as WAV (big-endian). |
| 35 | Apple Lossless (ALAC in M4A) | ✅ | should | Cheap once AAC works. |
| 36 | FLAC | ✅ ExtAudioFile `kAudioFileFLACType` + `kAudioFormatFLAC` (verified: valid 16-bit FLAC) ⚠️ verify on 14 | should | AVAssetWriter has no `.flac` file type; use ExtAudioFile. |
| 37 | Opus | ⚠️ Opus in CAF ✅; Opus in Ogg ❌ (write failed); Opus in MP4 accepted by `canApply` | later | Ogg/Opus is the format people mean; we can't write it cleanly. |
| 38 | CAF, AAC (ADTS `.aac`), AC-3, AMR | ✅ (ADTS verified) | later | Niche. |
| 39 | Vorbis (Ogg), WMA, MP2, Audio Book (m4b), WAV a-law/µ-law | ❌ Vorbis/WMA encoders; ✅ m4b, a-law/µ-law | skip | |
| 40 | iPhone Ringtone (m4r, ≤ 30 s) | ✅ (AAC in M4A container, `.m4r`, trimmed) | later | Cute, cheap after Trim. |
| 41 | Audio quality presets (Low/Medium/High/Ultra/Custom/Copy), channels, sample rate | ✅ | should (one Quality control) | AAC bitrate per Quality: 96 / 160 / 256 kbps. Channels and sample rate: as source. |

### Output formats: images

| # | Permute preset / output | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|
| 42 | **JPEG** (quality %, default 95 seen) | ✅ | **must** | Shared code with Squish (`ImageCompressor`). |
| 43 | **PNG** (interlaced, bits per sample) | ✅ | **must** | |
| 44 | **HEIC/HEIF** (quality %, default 90 seen) | ✅ | **must** | |
| 45 | **WebP** | ❌ **ImageIO decodes WebP but can't encode it**, even on macOS 27 (`org.webmproject.webp` missing from `CGImageDestinationCopyTypeIdentifiers`; destination creation fails). One forum post claims macOS 14 can write it; our test says no. | **can't** | In the roadmap spec. Open question 2. Squish made the same call. |
| 46 | AVIF | ⚠️ written on macOS 27 (`public.avif` in the writable list, valid AV1 still). **Verify on 14.** | should | Offer only when `CGImageDestinationCopyTypeIdentifiers()` includes it at runtime. |
| 47 | TIFF, BMP, GIF (still), JPEG 2000, ICO/ICNS | ✅ TIFF/BMP/GIF/JP2; ICO failed for a non-square image | later | TIFF is cheap; add if trivial. |
| 48 | JPEG XL | ❌ write (read ✅) | skip | |
| 49 | PNG Data URI | ✅ (base64 text) | skip | Developer niche, belongs in a dev tools app. |
| 50 | Image → Text (OCR) | ✅ Vision | skip | Different job. |
| 51 | Per-image filters (Core Image effects), colour replacement | ✅ | skip | Editing, not converting. |

### Adjustments and extras

| # | Feature | How Permute does it | Apple-only? | Priority | Notes for us |
|---|---|---|---|---|---|
| 52 | **Resize** (video and images) | Toggle + size constraints per preset or group | ✅ (`AVVideoWidthKey/HeightKey` + `ResizeAspect`; ImageIO thumbnail) | should | One popup: Original / 2160p / 1080p / 720p / 480p for video; longest edge for images. Never upscale. |
| 53 | File size restriction (target MB) | Video/audio: bitrate from duration; images: shrink until under | ✅ (bitrate math; `AVAssetExportSession.fileLengthLimit` exists) | later | Very useful ("under 25 MB for Discord"), but needs two-pass logic. v1.1 headliner. |
| 54 | **Trim** (in/out, nudge buttons, apply to group) | Sheet per file with preview, waveform for audio | ✅ (`timeRange`; passthrough trim verified to the exact second) | later (stretch) | Roadmap stretch goal. Needs a player sheet; not v1. |
| 55 | **Merge / stitch** (videos or audio end to end; images → PDF) | Group option; chapters per file; mixed sizes scaled down and letterboxed | ✅ (`AVMutableComposition`; passthrough merge verified) | later (stretch) | Roadmap stretch goal. Needs ordering UI. |
| 56 | **Extract audio** from video | "Export Tracks…" file action, or audio presets on a video | ✅ (`AppleM4A` preset on a video: verified) | **must (as a behaviour)** | Free with per-kind targets: Video target popup includes "Audio Only (M4A)" / "(WAV)". |
| 57 | Crop (with letterbox auto-detect) | Crop sheet with handles and saved sizes | ✅ (video composition / CI) | skip | Editing. |
| 58 | Rotate / flip | Group "Transformation" | ✅ | later | Rarely needed; AVFoundation keeps `preferredTransform`, so phone videos stay upright. |
| 59 | Speed change, volume boost | Group options | ✅ (`scaleTimeRange`, `AVAudioMix`) | skip | Editing. |
| 60 | Audio track / subtitle track management, burn-in subtitles | Per-file sheets | ⚠️ | skip | Pro feature. Default: keep the first audio track, drop subtitles we can't carry. |
| 61 | Split by chapters / CUE / EDL | File action | ✅ partly | skip | |
| 62 | Image + audio → video | File action | ✅ | skip | |
| 63 | PDF: images → PDF, PDF pages → images, Quartz filter | Presets | ✅ (PDFKit) | skip | PDF compress lives in Squish. |
| 64 | Text → speech, text encoding, transcribe (SRT) | Presets | ✅ (AVSpeechSynthesizer, Speech) | skip | Different jobs. |
| 65 | Metadata: copy (on), allow QuickTime metadata (location etc.), cover image, editor | Per preset | ✅ (AVFoundation copies common metadata; ImageIO copies properties) | should (keep metadata by default) | Keep metadata and orientation. An optional "Remove location" toggle could come later (privacy angle). |
| 66 | Preserve creation / modification dates | Destination pane, both off | ✅ | should | Off by default like Permute. Cheap to offer (Squish has `copyDates`). |
| 67 | Copy compatible tracks (no re-encode when the codec already fits) | On by default ("Copy Compatible Video/Audio Track") | ✅ (`AVAssetExportSession` does this: HighestQuality H.264 → MP4 of an H.264 source finished in 0.02 s, same size) | **must** | Huge speed win (MOV→MP4 remux is instant). Re-encode only when the codec, size or quality differs. |
| 68 | Hardware acceleration | Default for H.264/HEVC/ProRes | ✅ VideoToolbox | must (automatic) | Never expose it. |
| 69 | Presets editor (enable/disable, rename, duplicate, add, import/export, preview) | Settings > Presets | ✅ | skip | Our formats are a fixed, curated list. Quality is one popup. |
| 70 | "Automatic Setup" per preset (Small File / Compatible Small File / Good Quality / Best Quality) | Gear menu that rewrites the preset | ✅ | (adopted as Quality) | This *is* our Quality control. |
| 71 | Custom Groups (saved option bundles) | Settings pane, Load From… | ✅ | skip | |
| 72 | Drop Zones (floating tiles that convert on drop) | Window > Show Drop Zones ⇧⌘D | ✅ | later | Nice for repeat jobs. Our main window already converts on drop. |
| 73 | Destination: Same as source / Always ask / Choose folder; per-group override | Destination pane + group popover | ✅ | **must** (Next to Originals / Choose Folder…) | Same "Save to" control as Squish. |
| 74 | Include preset name in file name | Off | ✅ | — | We name `clip.mp4` next to `clip.mov`. If the name is taken (same extension or existing file), add a number: `clip 2.mp4`. Never overwrite. |
| 75 | Preserve subfolder hierarchy | Off | ✅ | later | Only matters with a chosen folder + folder drops. |
| 76 | Remove original after converting (to Trash) | Off | ✅ | later | Risky. If ever, Trash + undo. |
| 77 | When done: play sound (on), bounce Dock (off), quit app (off), sleep Mac (off), auto-remove finished (off) | General pane | ✅ | should (system sound + Dock bounce only when the app is in the background) | No custom sounds. Notification only if the batch took > ~30 s and the app isn't frontmost (opt-out toggle). |
| 78 | Keep the Mac awake while converting | Implied | ✅ (`ProcessInfo.beginActivity(.userInitiated, .idleSystemSleepDisabled)`) | **must** | Long encodes shouldn't stop at sleep. End the activity when idle. |
| 79 | Shortcuts action "Convert File" (files, preset, batch name, group, destination, crop) | App Intent | ✅ AppIntents | later | Good v1.1: "Convert Files" intent with format + quality. |
| 80 | URL scheme `permute://path?action=convert&preset=…&callback=…` | Used by Downie | ✅ | skip | Shortcuts covers automation. |
| 81 | Watch folders | Help explains a Folder Action + Shortcuts recipe | ✅ | skip | |
| 82 | Settings backup export, Debug menu (log, state dump, debug info for file) | App menu, Debug menu | — | skip | Not for a utility this small. |
| 83 | Anonymous analytics (on), in-app message download at launch, Setapp AI extension (`EneyIntegration.appex`), support button | Privacy pane, Help | — | skip | **No network**, per the design system. |
| 84 | GPL FFmpeg download, binary switcher | Binaries pane | — | skip | We ship no FFmpeg at all. |

### What Apple frameworks can't do that Permute can (decided)

| Can't do Apple-only | Decision |
|---|---|
| **Write MP3** | Not in v1. AAC/M4A is the default "compressed audio". Owner decides (open question 1). |
| **Write WebP** (still or animated) | Not in v1. Offer AVIF (where available) and HEIC/JPEG. Open question 2. |
| Write AV1, VP8/VP9, WebM, MKV, AVI, WMV, FLV, MPEG-1/2, Theora, DNxHD, HAP, Vorbis, Ogg/Opus, WMA, JPEG XL | Skip. README lists them as "use HandBrake/FFmpeg". |
| **Read** MKV, WebM, WMV/WMA, FLV, Xvid/DivX AVI, VP9 (even inside MP4) | Can't open (verified: "Cannot Open" / "Cannot Decode"). Row fails with a clear message: "Convert can't read MKV files. macOS has no reader for them." |
| Burn-in / convert bitmap subtitles, raw FFmpeg arguments | Skip. |

**What we can read** (verified on 27, ⚠️ verify on 14): MOV, MP4, M4V, 3GP, MPEG-TS/AVCHD,
MPEG-1/2 program streams (incl. MPEG-2 video), DV, AVI only with Apple-decodable codecs
(e.g. Motion JPEG), AV1 in MP4 (decode depends on chip/OS), MP3, AAC, M4A, WAV, AIFF, CAF,
FLAC, Opus/Ogg (⚠️), AC-3/E-AC-3, AMR. Images: everything ImageIO decodes, including HEIC,
AVIF, WebP, JPEG XL, RAW, PSD, TIFF, GIF, BMP, TGA, EXR.

**Key engineering findings for the build:**

- **Don't use the generic export presets for "quality".** `AVAssetExportPresetMediumQuality`
  silently downscaled a 1280×720 clip to **568×320**. The `NNNNxNNNN` presets cap size, and
  `HighestQuality` passes compatible tracks through. For our Quality control use
  **AVAssetReader → AVAssetWriter** with `AVVideoCompressionPropertiesKey`:
  `AVVideoQualityKey` (0.3 / 0.6 / 0.9 tested: 252 KB / 422 KB / 3.0 MB for H.264 on a 3 s
  720p clip; HEVC about 20–40% smaller) or `AVVideoAverageBitRateKey` for a size target.
  Keep `AVAssetExportSession` for passthrough (remux, trim, merge) and `AppleM4A`.
- `AVAssetExportSession.export(to:as:)` (async) is **macOS 15+**. On 14 use
  `exportAsynchronously` and poll `progress` (only while working).
- Reader/writer: feed video and audio inputs **concurrently** (`requestMediaDataWhenReady`
  per input). Feeding one track to the end first deadlocks the writer, which is waiting to
  interleave (hit this in the experiments).
- Video → GIF: `AVAssetImageGenerator` with zero tolerance plus `maximumSize` → ImageIO GIF
  with `LoopCount 0` and per-frame `DelayTime`.
- Audio: `AppleM4A` export works for MP3/FLAC/Opus inputs and for videos (= extract audio).
  WAV/AIFF/FLAC/ALAC via ExtAudioFile (decode to float, write PCM/FLAC/ALAC; verified) or
  AVAssetReader → AVAssetWriter (`.wav`, `.aiff`, `.m4a`). Passthrough to WAV fails for
  compressed input (expected).
- Image conversion is a superset of what Squish's `ImageCompressor` already does (ImageIO
  decode → optional downsample → encode). Reuse it, ideally via a shared module.
- Build the format menu from **runtime capability checks** (`CGImageDestinationCopyTypeIdentifiers`,
  `AVURLAsset.audiovisualTypes()`, `canApply(outputSettings:)`), not a hardcoded list, so AVIF
  shows only where it works and nothing breaks on 14.

### FileQueue: what it already gives us, and the gaps for Convert

Already there (`apps/SlopKit/Sources/SlopKit/FileQueue`): drop zone → list, folder expansion
(recursive, hidden files skipped, 5,000 cap, Finder sort), accepted-type filtering, duplicate
suppression, bounded concurrency off the main actor, per-item progress (throttled),
cancel / cancel all / retry / retry all / remove / clear finished, re-dropping a finished file
re-runs it in place with `previousOutput` (so we can overwrite our own earlier output),
outcomes (`produced` / `unchanged` / `skipped`), plain-language error text from
`LocalizedError`, Quick Look thumbnails, context menu (Show in Finder, Show Original, Process
Again, Remove), a summary for the status line, `onIdle` for the "done" signal.

Gaps to close in SlopKit (or wrap in the app):

1. **Size-change wording.** Rows always show a green "−N%" saved figure, and a bigger
   output shows a green "0%". Conversions often grow files (ProRes, WAV, PNG). We need a way
   to show a neutral "4.2 MB → 18 MB" with no percent, or a signed change in secondary colour
   (e.g. `FileQueueView(showsSavings: false)`).
2. **Row detail hook.** Waiting/done rows only show the byte size. We want the target and
   media info ("→ MP4 · 1920×1080 · 2:14"). Proposal: an optional `detail: (FileQueueItem) -> String?`.
3. **Per-kind concurrency.** One `maxConcurrent` for everything. Video should run at most
   1–2 at once (the media engine is shared; more just splits it and multiplies memory), while
   images can run wide. Options: a `concurrencyLimit(for: URL) -> Int` / weight per job, or a
   simpler app-side semaphore for video inside the processor.
4. **Context menu wording.** "Process Again" reads oddly for Convert; it should come from the
   app ("Convert Again"). Same for the drop strip text ("Drop more files here…" is fine).
5. **One output per job.** Fine for v1. Video → image sequence (later) would need
   `produced([URL])` or a folder output.
6. **Unsupported-but-media files.** `acceptedTypes` filtering silently drops e.g. `.mkv`
   (it conforms to `public.movie` but AVFoundation can't open it). Either accept broad types
   and fail the row with a clear message (preferred), or show a HUD "3 files skipped: MKV
   isn't supported".

## Key flows

### Flow 1: the main job (convert a screen recording to MP4)
1. Open Convert. The window shows a big drop zone: "Drop videos, audio or images", "or click
   to choose". The bottom bar shows the three targets with defaults: **Video: MP4 (H.264)**,
   **Audio: M4A (AAC)**, **Image: JPEG**, then **Quality: Balanced** and **Save to: Next to
   Originals**.
2. Drag `Recording.mov` onto the window. The drop zone turns into the queue. The row shows a
   thumbnail, the name, "→ MP4 · 2560×1600 · 1:12" and a progress bar. Encoding starts at
   once.
3. The row finishes: "512 MB → 38 MB", plus a Show in Finder button. `Recording.mp4` sits
   next to the original, which is untouched. If the window is in the background, the Dock
   icon bounces once with the system "done" sound.
4. Return / double-click shows it in Finder. Space opens Quick Look on the output.

Permute's version of this flow needs, after the drop: check the group's preset popup, press
Start, wait. Its default preset list hides most formats until you enable them in Settings.

### Flow 2: first run
1. No onboarding, no permission prompts. Convert needs **no TCC permissions**: it reads
   files the user dropped or chose and writes next to them. If it's sandboxed, it needs
   user-selected read/write plus a security-scoped bookmark for a chosen "Save to" folder.
2. Empty state = drop zone. Defaults are good enough that most users never open Settings.

### Flow 3: change format for one batch (images to PNG)
1. Before or after dropping, click the **Image** target popup → PNG.
2. New drops use PNG. To redo files already converted, select them and choose **Convert
   Again** (context menu or File menu), or re-drop them; FileQueue re-runs them in place.

### Flow 4: extract audio from videos
1. Video target popup → **Audio Only (M4A)** (or WAV).
2. Drop videos → `.m4a` files appear. A video with no audio track fails with "This video has
   no sound to extract."

### Flow 5: video to GIF
1. Video target popup → **GIF**. Quality maps to size and fps (Smaller: 480 px / 10 fps,
   Balanced: 640 px / 12 fps, Best: 800 px / 15 fps).
2. Long clips (> 30 s) still convert, with a caption on the row ("Long GIFs get big. Trim
   first for smaller files"). Trim itself is a later feature.

### Flow 6 (Permute): Drop Zones
Window > Show Drop Zones opens a floating window of tiles. Dropping on a tile starts
conversion with that tile's presets, with no confirmation. Tiles are defined in Settings.
Noted for later.

## Settings inventory (Permute 4.1, values seen)

| Pane | Setting | Value seen | Options | Keep? |
|---|---|---|---|---|
| General: when done | Play a sound | on | toggle | Keep as "Play sound when done" (system sound), on. |
| | Quit app | off | toggle | Skip. |
| | Put computer to sleep | off | toggle | Skip. |
| | Bounce icon in the Dock | off | toggle | Merge: we bounce once only if in background. |
| | Automatically remove completed conversions | off | toggle | Skip (Clear Finished is one shortcut). |
| General: performance | Enable thumbnail generation | on | toggle | Skip (always lazy). |
| | Low power mode | off | toggle (limits cores, 1 at a time) | Skip; sane concurrency instead. |
| | Maximum concurrent conversions | Default (automatic) | Default / numbers | Skip. |
| Destination | Destination | Same as source | Same as source / Always ask / Choose Folder… | Keep as Save to: Next to Originals / Choose Folder… (in the bottom bar, like Squish). |
| | Include preset name in file name | off | toggle | Skip. |
| Destination: metadata | Preserve creation date | off | toggle | Should: one toggle "Keep original file dates", off. |
| | Preserve modification date | off | toggle | (merged above) |
| Destination: processing | Process folders recursively | on | toggle | Always on (FileIntake). |
| | Preserve subfolder hierarchy | off | toggle | Later. |
| | Auto-start conversions from external sources | on | toggle | n/a (we always start on drop). |
| Destination: advanced | Remove original file | off | toggle | Later, Trash only. |
| | Remove original subtitle files | off | toggle | Skip. |
| Subtitles & Audio | Detect external subtitles; detect their language | on; on | toggles | Skip. |
| | Default subtitle encoding / language | UTF-8 / Unspecified | popups | Skip. |
| | Default audio track language | No Language Selected | popup | Skip. |
| Presets | 20 enabled presets (AAC, AppleTV 4K, Apply PDF Filter, GIF Animation, HEIF, HEVC (H.265), High Quality, iPad 3, iPhone 8, iPhone Ringtone, iPhone X, JPEG, M4A, MP3, MP4, PDF, PNG, Small File, Text to Speech, Video to Images); about 60 more in Add Preset (Video 31, Audio 15, Image 12, PDF 2, Text 3, Custom, Advanced Custom) | | Per video preset: Automatic Setup (Small File / Compatible Small File / Good Quality / Best Quality), Container, Video Format, Video Quality (Low/Medium/High/Ultra/Custom CQ or CRF/Copy), Copy compatible track (on), Resize, Framerate, Interlacement, Color handling, Keyframe interval, Profile (High), allow HEVC copy; Audio Quality, copy compatible audio (on), Channels, Sample rate; Copy subtitles (on), Burn subtitles (off); Copy metadata (on), Allow QuickTime metadata. Image: Compression % (JPEG 95, HEIF 90), extension, bits per sample, interlaced (PNG), Resize, File size restriction, Filters. GIF: Loop (forever). PDF: password, DPI 72, Resize. | Replace with fixed targets + one Quality popup + Resize. |
| Custom Groups | none | | saved option bundles | Skip. |
| Drop Zones | none | | tiles with colours, presets | Later. |
| Privacy | Send anonymous analytics | on | toggle | Skip: we send nothing. |
| Binaries | FFmpeg / Exiftool binary | Default | Default / GPL download / custom | Skip. |

**Our Settings** (`SlopSettings`): **General**: Play sound when done (on), Notify when a long
batch finishes in the background (on), Keep original file dates (off), Launch at login (per
design system; arguably pointless for a window app, see open question 6). **About**. Formats,
quality and destination live in the bottom bar, not Settings.

## Menus and shortcuts (Permute 4.1)

- **Permute**: About; Export Settings Backup…; Settings… ⌘,; Services; Hide ⌘H; Hide
  Others ⌥⌘H; Show All; Quit ⌘Q (Quit and Keep Windows ⌥⌘Q).
- **File**: Open… ⌘O; Start Conversions ⌘S; Pause All Conversions ⌘P; Clear Finished
  Conversions ⌘K; Schedule Start… ⇧⌘S; Close ⌘W; Close All ⌥⌘W.
- **Edit**: standard (Undo/Redo/Cut/Copy/Paste/Delete/Select All). ⌘V pastes files.
- **View**: Enter Full Screen.
- **Debug**: About Debug Log…; Debug Logging On/Off; Copy / Log Current Application State;
  Clear Debug Log; Show Log in Finder; Debug Information for File…
- **Window**: standard + Show Main Window ⌘0; Show Drop Zones ⇧⌘D.
- **Help**: Contact Support; Release Notes; Webpage; EULA; Privacy Policy; Permute Help.
- No global shortcuts, no menu bar item.

Notes: ⌘S for "Start" and ⌘P for "Pause" reuse Save/Print, which surprises Mac users. ⌘K
for Clear Finished is a nice touch.

**Ours** (proposed): File: Choose Files… ⌘O; Convert Again ⌘R (selected, or all finished);
Stop All ⌘.; Show in Finder ⇧⌘R; Clear List ⇧⌘⌫ (or ⌘K); Close ⌘W. Edit: Paste ⌘V (adds
copied files), Select All ⌘A, Delete = Remove from List. Format menu (or View): Video / Audio
/ Image target submenus and Quality, so every bottom-bar choice is in a menu (design system
§6). Space = Quick Look output. No global shortcuts.

## Permissions and system integration

- **TCC**: none. Permute asks for nothing at launch. We need nothing beyond user-selected
  file access.
- **Document types / Open With / Dock drop**: Permute accepts drops on its Dock icon. We
  declare movie, audio and image types as `LSHandlerRank = Alternate` so we never become the
  default app.
- **Services**: Permute adds "Add Selected File to Permute" (`NSFilenamesPboardType`). We
  could do "Convert with Convert" later.
- **URL scheme**: `permute://` (convert/stitch actions with preset, destination, trim, crop,
  callback URL). Skip.
- **Shortcuts**: one App Intent, "Convert File". Later for us.
- **Extensions**: `EneyIntegration.appex` (Setapp's assistant). Skip.
- **Bundled tools**: ffmpeg (LGPL build), cwebp, cjxl, exiftool (+ perl), anim_dump,
  IP264Fixer. That's how Permute covers 100+ formats. We ship none, by design.
- **Network**: analytics (on by default), a message `.plist` fetched at launch. We: none.
- **Requirements**: Permute 4 needs macOS 26 and Apple silicon (Permute 3 for older Macs). We
  target macOS 14, so a capability check matters more for us.
- **Power**: we hold a `beginActivity` assertion (idle sleep disabled) while busy, and drop
  it when idle.

## UX patterns worth adopting

- **Sort by kind, one target per kind.** Permute's automatic grouping means a mixed drop
  (video + photos) does the right thing for each. We get the benefit without the group UI:
  three target popups.
- **Pass compatible tracks through.** If the source is already H.264/AAC and only the
  container changes, copy instead of re-encoding: instant and lossless. Permute does this by
  default, and AVFoundation does it for free.
- **Quality as intent, not numbers.** Permute's "Automatic Setup" (Small File / Good
  Quality / Best Quality) is the useful layer; CQ/CRF/bitrates are an advanced escape. We ship
  only the intent layer.
- **Media facts on the row.** Resolution, codec, duration and size before you convert answer
  "what is this file?". That's the question behind most conversions.
- **Show the output where the input was**, keep the original, never overwrite.
- **⌘V to add copied files** and a Dock-icon drop: small, cheap entry points.
- **Large batches don't stop on one bad file**: a failure is just a row state (App Store
  reviewers praise this). FileQueue already works this way.
- **Trim sheet nudge buttons** (±10 s / ±5 s / ±0.1 s each side): good model for our later
  Trim, keyboard-first with ←/→ and ⇧←/⇧→.

## What we won't copy, and what we'll do better

- **Not copying**: the name, icon, the tinted capsule group headers, image-background cards,
  coloured Drop Zone tiles, the "Finished" sound, wording, presets catalogue, FFmpeg Advanced
  Custom, analytics, support/debug chrome, Setapp/assistant integrations.
- **Doing better**:
  - **Starts on drop.** Permute requires a separate Start (⌘S) after every drop. We start
    immediately with visible targets, and finished rows can be converted again.
  - **No hidden formats.** Permute ships ~20 presets enabled and ~60 hidden behind Settings >
    Presets > Add. Ours is a short, honest list that's always visible.
  - **Honest sizes.** Show "before → after" in neutral colours, with growth explained (ProRes
    and WAV are big on purpose).
  - **Clear "can't" messages.** MKV/WebM/WMV are refused with a sentence saying why, instead
    of a generic failure.
  - **Standard shortcuts.** No ⌘S = Start or ⌘P = Pause.
  - **Native look.** System list, accent colour, light and dark mode. Permute's custom dark
    capsules ignore light mode. One Setapp reviewer called the v4 redesign awful; another
    found the older UI weird.
  - **Quality that's predictable.** App Store reviewers complain that compression settings
    need tweaking and that bitrate can't be set exactly. Our three Quality levels map to
    documented quality values, and we never silently downscale (the trap in Apple's "Medium"
    preset).
  - **No network, no analytics, no forced messaging.** One reviewer complained about a
    non-optional political banner; Permute fetches remote messages at launch.
  - **Runs on macOS 14 and Intel** (where VideoToolbox allows), where Permute 4 needs macOS 26
    + Apple silicon.
  - **Keeps the Mac awake** during long encodes and reports progress in the Dock icon (should).

## Edge cases

- **Mixed drops**: video + audio + images + unsupported files in one drop. Each uses its
  kind's target. Unsupported files become failed rows with a reason (or one HUD summary),
  never silently vanish.
- **Unreadable containers**: `.mkv`, `.webm`, `.wmv`, `.flv`, Xvid `.avi`, VP9-in-MP4 → clear
  message naming the format. A truncated/corrupt file → "Couldn't read clip.mp4. It may be
  damaged."
- **DRM-protected media** (`.m4p`, protected `.m4v`/`.aax`): `isExportable == false` → "This
  file is copy-protected, so it can't be converted."
- **Same format in and out** (MP4 → MP4 H.264, Balanced): output name collision. Write
  `clip 2.mp4`, never overwrite. If it's pure passthrough with no changes, say "Already
  MP4. Nothing to change." (`unchanged`).
- **Output grows** (MP4 → ProRes, MP3 → WAV, JPEG → PNG): expected; neutral wording.
- **Video without audio** / audio-only target on a silent video → clear failure. **Audio with
  cover art** → keep artwork in M4A where possible.
- **Rotation**: phone videos with `preferredTransform`; output must stay upright (writer
  input `transform`). Images: bake EXIF orientation or carry it.
- **HDR / 10-bit / Dolby Vision** iPhone HEVC → H.264 (8-bit): needs tone mapping
  (`AVVideoColorPropertiesKey` to Rec.709, or export session). Check colours aren't washed
  out. HEVC → HEVC keeps HDR.
- **Variable frame rate** screen recordings and **odd dimensions** (H.264 needs even
  width/height; scale to even).
- **Multiple audio tracks** (e.g. screen recording with mic + system audio): v1 keeps the
  first enabled track, or mixes all (decide in build; document it).
- **Very long or very large inputs** (2 h, 20 GB): progress keeps moving, memory stays flat
  (streamed reader/writer), the Mac doesn't sleep, cancel stops within a second and removes
  the partial file.
- **Disk full / no write permission / source on a read-only volume or disconnected drive**
  → readable error, partial output deleted. "Save to" folder gone → fall back with a message.
- **App quit mid-encode**: confirm "Stop 3 conversions and quit?". Partial temp files are
  cleaned up (write to a temp name, then atomic move).
- **Sleep/wake** mid-encode: resumes (AVFoundation continues) or fails cleanly with retry.
- **Many files** (500 images, 50 videos): images in parallel, videos 1–2 at a time; list stays
  smooth (FileQueue slices big drops).
- **Animated inputs**: animated GIF/HEICS/WebP → JPEG takes the first frame (say so);
  GIF → MP4 is a nice later feature.
- **GIF size blowup** from long or large videos (cap dimensions, warn on long clips).
- **Non-English and emoji filenames**, names with `/`-like characters, very long names.
- **Dark/light mode**, Reduce Motion, VoiceOver labels for row actions and target popups
  (FileQueue rows already set accessibility labels).
- **macOS 14 vs newer**: AVIF write, FLAC/Opus, AV1 decode and the async export API differ by
  OS/chip. The format menu comes from runtime checks; test on a macOS 14 VM if possible.
- **Intel Macs** without HEVC hardware encode (pre-2017): HEVC falls back or is hidden.

## Our v1 scope

Must-haves (eight; everything else is should/later):

- [x] **Drop or ⌘O**: empty state is a `DropZone` ("Drop videos, audio or images"); folders
      are searched; more drops join the queue (FileQueue). Unsupported media fails in its row
      with a sentence naming the format.
- [x] **Converts on drop** using the target for the file's kind, shown in a bottom bar:
      **Video** (MP4 H.264 [default], MP4 HEVC, GIF, Audio Only M4A, Audio Only WAV),
      **Audio** (M4A AAC [default], WAV), **Image** (JPEG [default], PNG, HEIC).
      Choices persist. All choices are also in a menu.
- [x] **Quality: Smaller / Balanced [default] / Best**, mapped to `AVVideoQualityKey` (video),
      AAC bitrate (audio), JPEG/HEIC quality (images) and GIF size/fps. Never upscales,
      never silently downscales.
- [x] **Passthrough when possible**: a container-only change (e.g. H.264/AAC MOV → MP4) is a
      remux, not a re-encode. Re-encoding happens only when the codec, size or quality needs it.
- [x] **Queue rows** (FileQueueView): thumbnail, name, target, progress, before → after
      sizes in neutral wording (no green "saved %"), Cancel / Try Again / Show in Finder,
      double-click/Return reveals, context menu Convert Again / Remove. Video runs 1–2 at a
      time; images in parallel; the UI never blocks.
- [x] **Output next to the original** (`name.newext`, or `name 2.ext` when taken) or into a
      chosen folder (Save to: Next to Originals / Choose Folder…). Never overwrites, writes via
      a temp file + atomic move, keeps metadata and orientation, never touches the original.
- [x] **Stays awake and finishes cleanly**: power assertion while busy; Stop All ⌘.; quitting
      while busy asks first; cancelled/failed runs leave no partial files.
- [x] **Standard app pieces**: menus with shortcuts for every action (Choose Files… ⌘O, Convert
      Again, Stop All ⌘., Show in Finder ⇧⌘R, Clear List, Paste ⌘V adds copied files),
      Settings (General: sound when done, keep file dates; About), light/dark, VoiceOver
      labels.

Should (v1 if cheap): media info on rows (resolution · codec · duration); Space = Quick Look
output; Dock-icon drop / Open With; AIFF, ALAC, FLAC, ProRes 422, AVIF (runtime-gated);
Resize (Original / 1080p / 720p / 480p, image longest edge); keep original file dates; Dock
progress + bounce when done in the background.

Later (v1.1+): Trim, Merge (roadmap stretch goals), target file size, Shortcuts action,
Finder Quick Action/Service, Drop Zones, video → image sequence, APNG, ringtone, rotate,
remove-location toggle.

## Decisions

Owner defaults (2026-11-03), recorded as given:

1. **MP3: no encoder.** Apple frameworks only, no LAME/LGPL. Audio defaults to M4A (AAC);
   WAV and AIFF (plus Apple Lossless) are the lossless options. The UI doesn't show a disabled
   MP3 item; the README ("What it can't do") explains why there's no MP3.
2. **WebP output: no.** WebP inputs are read fine. AVIF is offered where this Mac can write it.
3. **Start on drop: yes.** Changing a target doesn't touch finished rows; "Convert Again"
   (⌘R, the bar's button when settings changed, the context menu) re-runs them.
4. **Images: simple ImageIO code inside Convert** (`ImageConverter`), not shared with Squish.
5. **GIF: 640 px / 12 fps for Balanced** (480/10 Smaller, 800/15 Best); clips over 30 s
   convert with a "Long clips make big GIFs." note on the row, before and after.
6. **No Launch at login** (window app). Settings is built from SlopKit's `SettingsForm` and
   `AboutSettingsTab` directly, because `SlopSettings`' General tab always adds the toggle.
7. **FileQueue changes approved, additive only** (see build notes).

Decided while building:

- **640 px means the long edge**, so a portrait clip is 360×640, not 640×1138.
- **Copy vs re-encode rule:** a track is copied when its codec already fits the target and
  no resize is needed, unless Quality is **Smaller** (which always re-encodes video, and
  re-encodes AAC above 1.25× the Smaller bit rate). A file whose plan is a pure copy into the
  same container is left alone: "Already MP4 (H.264). Nothing to change. To make it smaller,
  choose Smaller under Quality."
- **Never overwrite, even our own output.** Convert Again writes "clip 2.mp4" rather than
  replacing this session's "clip.mp4" (the owner's "outputs never overwrite").
- **Several sound tracks are mixed into one** (`AVAssetReaderAudioMixOutput`), with a note on
  the row; more than two channels become stereo. One track with ≤ 2 channels is copied when it
  fits.
- **Bad frames at the very end** (seen in a real Apple wallpaper video: the last 0.075 s can't
  be decoded) don't fail the file: if ≥ 97% was read, it's kept with a note "The last moment
  couldn't be read, so it was left out." Earlier read failures fail the row ("may be damaged").
- **H.264 over 4096×2304** is scaled to fit with a note pointing to HEVC.
- **HDR → H.264** is tone-mapped to Rec. 709 (note on the row); HDR → HEVC/ProRes keeps
  10-bit and the source's color tags.
- **GIFs are streamed** (`GIFStreamWriter`): ImageIO's animated-GIF writer keeps every frame
  until it finishes (a 60 s clip peaked at 1.16 GB). Each frame is encoded alone by ImageIO
  and only the changed rectangle is stored, with unchanged pixels transparent. Memory stays
  flat (~55–85 MB) and files came out smaller than ImageIO's (34 MB vs 50 MB for 60 s of
  4K video; 228 KB vs 366 KB for the 6 s fixture).
- **Video quality values** calibrated on Apple's "Golden Gate" wallpaper video (natural
  footage, not personal content) at 1080p: Smaller 0.40 shows visible blocking (as intended),
  Balanced 0.55 looked the same as the source in a 1:1 crop, Best 0.75 ≈ 3× Balanced's size.
- **Sound when done** plays only for batches that took ≥ 3 s or finished while Convert was in
  the background (instant photo drops stay quiet). No notifications (they'd need a
  permission prompt; the Dock bounce covers "done while away").
- **⌘C copies converted files, ⌘V adds copied files**; Convert has no text to edit, so the
  Edit menu's pasteboard group is replaced. `CONVERT_PASTEBOARD` points both at a private
  pasteboard for scripted tests.
- **Scratch files** live in macOS's per-volume "item replacement" folder (same volume, so the
  final step is an atomic `renamex_np(RENAME_EXCL)`), falling back to a hidden file next to
  the output. They're removed on success, failure and cancel, and the OS cleans that folder
  if the app is killed.
- **Unsupported drops** (e.g. `Notes.txt`) become failed rows: "Notes.txt isn't a video, audio
  file or image. Convert works with videos, audio files and images." Unsupported files *inside
  dropped folders* are skipped silently.

## Build notes

**SlopKit FileQueue additions** (additive; Squish unchanged, its 42 tests pass):
`.fileQueueSizeStyle(.neutral)` (no green "−N%"), `.fileQueueDetail { item in … }` (row
detail slot: after the size while waiting, beside the progress bar while working, after
before → after when done; also read by VoiceOver), `.fileQueueRetryTitle("Convert Again")`,
`FileQueue.lane` + `laneLimits` (per-kind concurrency: video 1, or 2 on 10+ core Macs; audio
4; images up to `maxConcurrent`), `FileQueue.unsupportedReason` (failed rows with a reason;
drops then accept any file), `FileQueue.onBusy` (pairs with `onIdle`; drives the sleep
assertion), `FileIntake.unaccepted`. 5 new SlopKit tests (36 total).

**Tests:** 45 Convert tests, all real conversions of synthetic media read back with
AVFoundation/ImageIO (codec, size, duration, track count, bit depth, loop count, frame
timing, metadata, HDR tags) plus frame-colour comparisons against the source, never-overwrite,
cancel/failure leave nothing behind (visible folder and scratch), destination errors, the
planner's copy/re-encode matrix, and the sleep assertion with a fake.

**Gates (2026-11-03):** `scripts/check.sh Convert --perf` green: launch 155 ms, first window
300 ms, idle CPU 0.014%, footprint 35.5 MB (budget 120). During a 60 s 4K HEVC → 1080p H.264
encode the footprint stayed 66–71 MB; a 60 s GIF stays ~55–85 MB.

**Walkthrough** (release build, `scripts/drive`, fixtures under `/tmp/convert-test/`): empty
state, mixed drop via `open -a` (videos, photo, WAV, `.txt`, `.mkv`) → right targets, MKV and
text rows explain themselves; folder drop (nested, `.txt` inside skipped); GIF with the long
clip warning; quality/size/target menus in the bar and the Format menu; Convert Again after a
target change (bar button and ⌘R); ⌘V/⌘C via a private pasteboard; Quick Look ⌘Y; context
menu ("Convert Again"); Save To a folder; Settings and About; Stop All mid-encode (no partial
file, `pmset -g assertions` shows "Convert is converting files" while busy and nothing after);
⌘Q mid-encode asks "Stop converting and quit?" and leaves nothing behind. Light and dark
screenshots in `/tmp/convert-test/shots/`. `scripts/drive tree` shows no `[unlabeled]`
controls (the only one seen was the system open panel's search field).

**Design checklist (§10):** 1 pass (drop converts at once); 2 pass (system controls, accent,
light/dark); 3 pass (every action and every bar choice in File/Edit/Format menus with
shortcuts); 4 pass (Esc closes Quick Look/menus, ⌘, ⌘Q ⌘W); 5 pass with the owner's
exception (no Launch at login); 6 pass; 7 pass (drop zone with symbol, one line, click to
choose); 8 n/a (no permissions); 9 pass (nothing is ever deleted or overwritten); 10 pass (no
network code); 11 pass; 12 pass; 13 pass (only SlopKit's drop-zone scale, which honours Reduce
Motion); 14 pass (window frame and all choices persist).

**Deferred from "should":** FLAC output (needs an ExtAudioFile path; AVAssetWriter has no
FLAC file type), progress on the Dock icon, Finder Quick Action. "Try Again" still shows on
rows that can never work (MKV, `.txt`); a FileQueue "not retryable" flag could hide it later.

## Sources

- Permute product page: https://software.charliemonroe.net/permute/
- Permute 4 on the Mac App Store: https://apps.apple.com/us/app/permute-4/id6774079417?mt=12
- Permute 3 on the Mac App Store (reviews): https://apps.apple.com/us/app/permute-3/id1444998321
- Setapp customer reviews: https://setapp.com/apps/permute/customer-reviews
- MacStories review: https://www.macstories.net/reviews/permute/
- ifun.de on Permute 4 requirements: https://www.ifun.de/permute-4-veroeffentlicht-medienkonverter-setzt-kuenftig-apple-chips-voraus-281646/
- AlternativeTo (alternatives: HandBrake, Morpholder, Frame…): https://alternativeto.net/software/permute
- Extended FFmpeg build note (Binaries help): https://software.charliemonroe.net/permute/ffmpeg/
- Permute's built-in help (bundled JSON in the app: getting started, groups, editing, file
  actions, quality, presets, drop zones, automation, stitching, subtitles, watch folders,
  scheduled start, privacy, binaries).
- Core Audio list on MP3 encoding not shipping in macOS:
  https://lists.apple.com/archives/coreaudio-api/2012/Jun/msg00032.html
- Our experiments (macOS 27.2, M4 Max, 2026-11-03): ImageIO read/write type lists,
  `AVURLAsset.audiovisualTypes()`, export presets, AudioToolbox encoders and writable file
  types, AVAssetWriter `canApply` matrix, real encodes (H.264, HEVC, ProRes, M4A, WAV, AIFF,
  FLAC, ALAC, ADTS AAC, Opus-in-CAF, GIF, JPEG, PNG, HEIC, AVIF, TIFF, BMP, PDF), passthrough
  remux/trim/merge, reader/writer quality sweep, and read tests on MKV/WebM/AVI/WMV/WMA/
  MPEG-2/TS/AV1/VP9/FLAC/Opus/MP3 inputs.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Outputs were correct every time. Triage by the coordinator; all accepted.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 ⌘W / close button mid-conversion: window vanishes, then "Stop converting and quit?" loops; Cancel later quits and loses the list | major | accept | SlopKit's `SlopAppDelegate` says "terminate after last window closed", so closing started quitting before anyone confirmed. Fix (in Convert): `WindowCloseGuard` wraps the window's SwiftUI delegate and asks "Stop converting and close?" in `windowShouldClose` (Cancel keeps the window and the work); `applicationShouldTerminateAfterLastWindowClosed` returns false while busy. ⌘Q unchanged. Verified: Cancel keeps converting; Stop and Close quits with no partial file and no sleep assertion. Cleaner SlopKit fix for all window apps: a `confirmsCloseWhileBusy` hook on `SlopAppDelegate` (or `FileQueueView` owning this guard). |
| F2 Convert Again with no selection redoes every row, writing identical "… 2" copies | major | accept | Each row remembers the settings signature it ran with (target, plus quality/size only where they matter for that kind, plus destination). Convert Again without a selection redoes only rows whose signature changed (plus failed/stopped ones); a note above the bar says "N files were converted with other settings. [Convert Again]" (replaces the bar button). With a selection it redoes exactly the selection, and the menu item reads "Convert Selected Again". A re-run replaces the row's own earlier output (same folder and extension, atomic `rename`) instead of adding "2" copies; nothing else is ever overwritten. Tests cover replace / new target / never the input. |
| F3 New rows land off-screen in a long list | minor | accept | SlopKit `.fileQueueFollowsNewFiles()` (opt-in): scrolls to new rows (first of a batch at the top, a single file at the bottom) and tints them with the accent colour for 1.5 s. |
| F4 Footer pop-ups lose their accessibility name; icons vanish when Convert Again appears | minor | accept | Every footer menu always has its icon (AppKit takes the name from the icon's description); Convert Again moved out of the bar; window min width 720 so they always fit. |
| F5 List ignores arrows/Space/Delete until Tab | minor | accept | Same modifier focuses the list when it appears and on every new batch. Verified arrows move the selection right after adding files. |
| F6 Orange error text on blue selection | nit | accept | Failed rows use the selected-text colour when selected in the key window (SlopKit row; Squish benefits too). |
| F7 Title count off; "Up to" vs "Max"; Try Again on hopeless rows; Esc on About; GIF cap not stated | nits | accept | Title "Converting… 4 of 5 done"; bar says "Up to 1080p" like the menu; new `FileQueueRetryHint` (SlopKit): unreadable/unsupported/damaged/protected/empty rows show no Try Again and are skipped by Convert Again; Esc closes About (local key monitor); Size menu ends with "GIFs are capped at 640 px (800 px with Best)", the tooltip says it, and capped GIFs get "GIFs are capped at 640 px. Best makes them 800 px." on the row. |
| F8 Clear List can't be undone | nit | accept | Asks first while files are converting ("Stop N conversions and clear the list?"). Undo deferred (finished rows lose nothing on disk). |
| Missing: animated GIF → MP4 | — | accept | Animated GIF/PNG/WebP/HEICS are treated as silent videos: frames via ImageIO → AVAssetWriter (H.264/HEVC/ProRes), timing from the frame delays, tagged sRGB so colours match (untagged came out visibly lighter). GIF target on a GIF: "Already GIF."; other animations → GIF via the streaming writer. |
| Missing: Best audio seemed ~80 kbps | — | accept | The table was right (96/160/256 stereo) but the AAC encoder's default strategy undershoots on simple sound (the tone fixture came out ~50 kbps at Balanced). Now constant bit rate, tested within ±10%; rows show "160 kbps". |

Gates after the fixes: `scripts/test.sh SlopKit Squish Convert` 63 / 47 / 47 passing; `scripts/check.sh Convert --perf` green (launch, first window, idle CPU and 35.6 MB footprint within budget).

### Round 2 (2026-11-03)

Conversions excellent; one major. Triage by the coordinator.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 `open -a Convert.app file` (Open With, Dock drop) while open: window disappears, app quits or stays windowless, bogus "Stop converting and quit?", once wedged in `terminate:` | major | accept | **Cause:** round 1's `WindowCloseGuard` replaced the window's delegate (SwiftUI's `AppKitWindowController`) with a forwarding proxy. SwiftUI then lost track of its window, so an open-documents event made it close and recreate the scene window; the close triggered terminate-after-last-window (and the busy alert when the new file had started), and the round 1 `terminateLater` wait loop could wedge. Reproduced 2 of 3 tries before the fix, 0 of 4 with the guard removed. **Fix:** the guard no longer touches the delegate; it retargets only the close button, and ⌘W goes through the same confirmation. `applicationShouldTerminate` is back to a plain confirm → `terminateNow` (scratch files live in macOS's temporary-items folder, never next to originals). Files opened by any route bring the one window forward and join its list. Added Window ▸ Convert (⌘0) and Dock-click reopen when there's no window. **Regression check:** `apps/Convert/Tools/open-while-running.sh 10` opens 10 files one by one with `open -a` and asserts 1 process, 1 main window, no alert and N rows each time: 10/10 ok. Also checked while a 60 s 4K encode runs, and the close button / ⌘W confirmation (Cancel keeps working; Stop and Close quits clean). |
| F2 Window vanished once after Format ▸ Image ▸ PNG | minor | accept (same cause) | The delegate proxy again: any scene update could make SwiftUI replace the window it no longer recognised. With the proxy gone, 10 image-format and 3 quality changes in a row keep the same window. |
| F3 Bottom pop-ups still lose their name ("JPEG, menu button") | minor | accept | Found the trigger: once the list takes keyboard focus (round 1's follow-new-files), SwiftUI renames its `Menu` buttons to their value and ignores `.accessibilityLabel`. A Picker stand-in fixed the name but VoiceOver couldn't open the real menu. Now the bar uses `BarMenuButton` (in-app, AppKit pull-down `NSPopUpButton`, named so it can move to SlopKit): AX title is always "Image format" etc., value separate ("PNG"), AXPress opens the menu, items keep checkmarks and subtitles. Verified before and after files are added. |
| F4 Bigger output not explained | nit | accept | Rows add "Bigger than the original: …" when the output is over 5% bigger, with the reason: lossless/uncompressed target, GIF, H.264 from HEVC/AV1 ("Choose MP4 (HEVC) to stay small"), Best quality, or "choose Smaller under Quality". |
| F5 Undo for Remove from List / Clear List | nit | accept | ⌘Z puts removed rows back exactly as they were (results, failures, stopped), without converting anything again; ⇧⌘Z removes them again. Works for every removal route (File menu, Delete key, right-click menu, Clear List) by watching the rows; a `RestoreBook` hands the old outcome to the processor instead of converting. Verified: no new files on disk after undo/redo. Rows come back at the end of the list. |

Gates: `scripts/test.sh SlopKit Squish Convert` 65 / 51 / 47 passing; `scripts/check.sh Convert --perf` green (launch 173 ms, first window 298 ms, idle CPU 0.023%, footprint 38.0 MB); `open-while-running.sh 10` 10/10.


## Parity pass (2026-11-03)

Per [`docs/parity-pass.md`](../parity-pass.md): look and work much more like the original,
fill feature gaps. Sources: Permute 4.1's official screenshots (main window, trim, file
actions, presets pane; downloaded to `/tmp/convert-parity/web/`, not committed) plus the
earlier read-only walk of the installed app (menus, every Settings pane, preset options).
Permute wasn't launched again: last time it never showed files added to it, and the official
screenshots show the populated layout.

### How the original is laid out (what we matched)

- **Groups by kind.** Files sit in groups (Images, Video…), each under a full-width tinted
  header: ▷ Start, the group's **preset popup** (its format), name and "N files", then +, an
  options button, clear ⊗ and a fold chevron. Headers stay pinned while scrolling.
- **Cards in two columns.** Each file is a wide card with its **thumbnail filling the
  background** under a dark scrim: name in bold, a facts line ("1280×720 · H.264 · 7001 kbps
  · 41.27 fps · AAC · 49 kbps · Mono · 33.9 MB"), ⊗ top right, and a **bar along the bottom**
  with ▷/progress ("Converting 16% – 02:34", "Waiting…", "Finished.") and per-file tools
  (crop, trim, audio tracks, subtitles, options).
- **Status bar** along the window bottom: +, a centred count ("13 Conversions · 6 Running · 7
  Finished"), a support button.
- **Trim sheet**: big preview, a range bar with in/out handles, nudge buttons each side, the
  range readout in the middle, an actions menu, Cancel / Done.
- **Settings**: General, Destination, Subtitles & Audio, Presets (list with checkboxes → form),
  Custom Groups, Drop Zones, Privacy, Binaries.

### Gap table

| Item (Permute) | Status | Notes |
|---|---|---|
| Groups by kind with header (Start, format popup, name + count, +, options, clear, fold), pinned | **done** | `GroupHeader`: ▷ when something is ready, the kind's format popup, "Video / 3 files", +, ⋯ (merge, select all, reset per-file settings, remove finished), ⊗, chevron. Accent tint at 10% instead of Permute's coral. |
| Cards with thumbnail background, name, facts line, ⊗ | **done** | `CardView`: Quick Look frame/photo fills the card under a dark scrim; facts line from `MediaInfo.cardLine` (size · dims · codec · fps · audio codec · kbps · channels · length); a third line for the result, notes or the file's own edits. Sound files get the accent colour and a waveform symbol (Quick Look has no picture for them). |
| Card bottom bar with state, progress and tools | **done** | ▷ Start / ■ Stop / 🔍 Show in Finder / ↻ Try Again; "Ready → MP4", "Converting 42% → MP4", "Done · 200 KB → 101 KB", "Settings changed"; progress fills the bar; tools: trim, rotate/flip, sound, the file's format. |
| Two-column grid | **done** | Adaptive: as many 330 pt columns as fit (2 at the default width). |
| Status bar (+, count, support) | **done (adapted)** | +, Start (when files are ready), "9 files · 5 ready · 3 converting · 1 failed", then Presets, Quality, Size, Save To (Permute keeps those in presets/group options; ours stay one click away). No support button (no accounts, no network). |
| Manual Start (▷ per file/group/all, ⌘S) | **done (option)** | Settings › General › "Start converting as soon as files are added" (on, the owner's start-on-drop decision). Off: files wait as "Ready" cards; ▷ on a card, a header, the status bar, or File › Start ⌘↩ (not ⌘S, which is Save everywhere else). |
| **Per-file format** | **done** | Each card's format popup: "Same as Group (MP4 (H.264))" or any format of its kind; works on the whole selection. `FileOptions` per file (`OptionsBook`, read by the processor when the file starts). |
| **Presets incl. device presets** | **done** | Status bar Presets menu and Format › Presets: iPhone & iPad, Apple TV 4K, Older Devices & Windows, Web & Email, Chat GIF, Video Editing (each sets every format + quality + size), shown only if this Mac can write them. **Save Current Settings as Preset…**; Settings › Presets lists built-in and saved (use, rename, reorder, delete). Permute's per-preset codec forms (CRF, keyframes, profile…) are skipped on purpose: Quality stays intent-based. |
| **Trim** | **done** | Sheet: AVKit player, range bar (drag handles, click to scrub, VoiceOver-adjustable), −1s / −0.1 s / Set (I, O) / +0.1 s / +1s on each side, readout, Keep Everything, Cancel / Done. Copies stay copies (an H.264 .mov trimmed to .mp4 isn't re-encoded; the edit list cuts at the exact time). GIFs trim too. Not done: ±5/±10 s, frame steps, audio waveform, "apply to whole group" (S each). |
| **Merge files** | **done** | ⇧⌘M, the group ⋯ menu, or right-click: a sheet to order the files (drag or ↑/↓), then one file "First Merged.mp4". Videos of another shape are fitted with black bars; files without sound get silence; sound files merge to the Audio format; video → audio-only targets merge just the sound; GIF target merges to MP4 (H.264) with a note. Not done: chapters per file (S), images → PDF (M). |
| **Extract audio** | done (before) | Video format "Audio Only (M4A/WAV)", now also per file. |
| **Image resize** | done (before) | Size menu (fits a box either way round, never enlarges). |
| **Audio track selection** | **done** | Card sound menu on videos: "All Tracks, Mixed" (default), each track by number/language/codec/channels, or "No Sound". |
| Subtitle track selection / burn-in | **deferred (M, ~1 day)** | AVFoundation can pass tx3g/WebVTT tracks through to MP4/MOV, but we need a subtitle fixture writer, per-track UI and tests; burn-in needs Core Text drawing in the composition. |
| **Rotate / flip** | **done** | Card menu, right-click, Edit File menu (⌥⌘R / ⌥⌘L, flips): turns of videos go in the track matrix (lossless, instant, still a copy when possible); mirrors redraw through an `AVVideoComposition`; photos are drawn upright (orientation 1). Math in `PictureTransform` (the 8 turn/mirror combinations, EXIF orientations, matrices), tested. |
| Watch folders | **deferred (M, ~1 day)** | Permute itself does this with a Folder Action + Shortcuts recipe. Ours needs an FSEvents watcher, loop protection (outputs landing in the watched folder), a Settings list and a running app. |
| **After-conversion actions** | **done** | Settings › General › When Done: play a sound (on), remove finished files from the list (Undo brings them back), move originals to the Trash (only when the new, non-empty file exists elsewhere; `Trasher` protocol, faked in tests), quit Convert. Dock bounce when in the background (before). "Put the Mac to sleep" skipped: it changes system state, and isn't something a converter should do. |
| Crop | deferred (M, ~1 day) | The composition path exists, so encoding is easy; the work is a crop sheet with handles, presets and letterbox detection. |
| File size restriction ("under 25 MB") | deferred (M) | Bit-rate targeting from duration, two passes for accuracy. |
| Speed, volume | deferred (S–M) | `scaleTimeRange`, `AVAudioMix`. Editing more than converting. |
| Drop Zones, Custom Groups | deferred (M) / covered | Drop Zones: floating tiles per preset. Custom Groups ≈ our saved presets. |
| Video to images, split by chapters, edit metadata, Shortcuts action, Finder service, schedule start, pause | deferred / skip | Video to images needs several outputs per row (FileQueue change in SlopKit). Others as in the inventory above. |
| Settings panes | **done (fewer)** | General, Destination, Presets, About (SlopKit `SettingsForm` / `AboutSettingsTab`). Subtitles & Audio waits for subtitles; Privacy and Binaries don't apply (no analytics, no FFmpeg). |
| MP3 / WebP output, MKV/WebM read | can't | Unchanged: no encoder/reader in macOS (see "What Apple frameworks can't do"). |

### Deviations from the design system (and why)

- **Cards are always dark-styled** (dark scrim over the picture, dark appearance for their
  text and controls) in light and dark mode: text has to stay readable over any photo or
  frame, as in the original. The window around them follows the system appearance.
- **Custom card grid instead of SlopKit's `FileQueueView` list** (still on `FileQueue` for the
  queue itself): the shared view only has list rows. The grid reimplements selection (click,
  ⌘-click, ⇧-click), arrows (by column), Space, Return, Delete, drop anywhere, scroll to new
  files, and Quick Look.
- **Group headers tinted with the accent colour** (10%) over the bar material, not the
  original's coral.

### Shared components built in-app (candidates for SlopKit)

- `CardQueueView` / `CardView` / `CardThumbnails` (a card grid over `FileQueue`, grouped,
  with pinned headers): could become `FileQueueCardsView`.
- `RangeSlider` (two handles + playhead, VoiceOver-adjustable) and `PlayerView` (AVKit).
- `BarMenuButton` gained icon-only, dark and highlighted styles.

### CI fix

GitHub's macOS 26 runners are virtual Macs with no media engine; Convert's test job ran past
the 45-minute limit (the log stops after the build because `swift test` output is buffered
to the log file, so the hanging test isn't named). Changes:

- Tests that really encode video or HEIC carry `.needsMediaEngine`, which skips them when
  `CI` is set (`TestEnvironment.isCI`); they all run locally. With `CI=true`, 38 of 65 tests
  still run (planner, options, presets, after-actions, audio, PNG/JPEG/TIFF images, merge of
  sound), and the suite finishes in about 1 s.
- Every suite with real conversions has `.timeLimit(.minutes(5))`.
- The transcoder now watches the writer while feeding: a writer that fails (an encoder that
  gives up, a full disk) stops asking its inputs for more, which used to leave the feeds
  waiting forever. Now they're stopped and the file fails with a message.
- The fixture maker gives up after 20 s without progress (it used to spin up to 200,000
  times) and fails at once when its writer fails.
- `CI=true scripts/check.sh Convert`: 30 s here with a warm build (tests ~1 s).

### Gates (parity pass)

- `scripts/check.sh Convert --perf`: green. 65 tests in 9 suites (18 new). Launch 153 ms,
  first window 291 ms, idle CPU 0.017%, footprint 40.7 MB (budget 120).
- `CI=true scripts/check.sh Convert`: green in 30 s.
- **Walkthrough: partial, the screen was locked the whole session.** With the Mac locked,
  macOS hides windows from Accessibility and screen capture, so `scripts/drive tree / click /
  shot` couldn't run (re-checked over about an hour). Instead the release build was driven
  with `open -a` (files in), env-gated review hooks (`CONVERT_REVIEW=trim|merge|settings|edits`
  open a view or apply per-file settings as the card tools would), and `CONVERT_SNAPSHOT`,
  which saves PNGs of the app's own windows. Checked that way, light and dark: grouped cards with
  facts and results; manual-start mode ("Ready" cards, ▷ on header and status bar, MKV
  explained before Start); per-file HEVC + trim on a video (28 KB, "Trimmed to 0:00.5 –
  0:02.0", tools highlighted); per-file rotate on a PNG → JPEG (marker moved top-left →
  top-right, transparency on white); per-file WAV on a WAV ("Already WAV. Nothing to
  change."); trim sheet; merge sheet; Settings › General; When Done → move original to the
  Trash and remove finished (the folder kept only the new file; the list emptied).
  Idle with 5 cards: 0.04% CPU, 67 MB footprint (stable).
- **Not tested: owner away, screen locked** (needs an unlocked screen): `scripts/drive tree`
  for `[unlabeled]` controls (every new control has an explicit label or a combined
  accessibility element; the trim bar's track is hidden in favour of its two adjustable
  handles), clicking card tools and menus, the trim sheet's player and keys (I/O/Return/Esc),
  keyboard selection on the grid, Settings › Destination and Presets panes, and real
  screenshots with `scripts/drive shot`. Blind testers should cover these first.
- Snapshots (from the app's own windows, not the screen): `/tmp/convert-test/shots/parity/`
  `01-light-cards-per-file-edits.png`, `02-dark-manual-start.png`, `03-trim-sheet.png`,
  `04-merge-sheet.png`, `05-settings-general.png`, `06-dark-empty-after-remove-finished.png`.

## Polish pass (2026-11-05)

Per [`docs/polish-pass.md`](../polish-pass.md). Release build (`build/Convert.app`, real SDK
stamp), driven with `scripts/drive` (AX only: the owner was active the whole session, so no
real-pointer or global-key input), test files in `/tmp/convert-test/polish/`, screenshots in
`/tmp/slopapp-polish/convert/` (`before-*` and `after-{light,dark}-*`). Convert's defaults
domain was exported first and re-imported at the end (identical to the backup).

### Defects found and fixed (before → after)

| # | Surface | Defect | Before | After |
|---|---|---|---|---|
| 1 | lint | Corner literals | 11 (12, 8, 10, 7) | 0: `CardMetrics.radius` = `Radius.l`; bar `Radius.nested(in: l, padding: 6)` = 6; header pill `Radius.nested(in: l, padding: 6)` = 6; drop outline `Radius.m` |
| 2 | lint | Hardcoded colours | 5 | 0: all in `FixtureMaker` (synthetic test-pattern pixels, not UI), marked `// lint:allow` |
| 3 | lint | Spacing literals (warn) | 2 (`28`, `3`) | 0 (`Spacing.xxl + xs`, `Spacing.xs`) |
| 4 | Card | Status bar radius vs card | 8 pt inside a 12 pt card at 6 pt inset (not concentric) | 6 pt (concentric); progress fill now a straight edge clipped to the bar's shape (was its own 8 pt pill, min 8 pt wide) |
| 5 | Grid | Group header edges vs cards | header 12–848 pt, cards 16–844 pt (4 pt off each side) | both 16–844 pt |
| 6 | Grid | ▷ column | header ▷ 34.5 pt, card ▷ 32.5 pt, name 28.5 pt | 33 / 33 / 33.5 pt |
| 7 | Grid | Right column | header chevron 18 pt, format chevron 17 pt, ⊗ 15.5 pt from the edge | 15 / 15 / 15.5 pt |
| 8 | Card/header | Hit targets and shared heights | pop-ups 20×15, 24×13, 92×15; ⊗ 15×15; header ▷ 9×11; status-bar + 10×10; trim 22×22 | every tool, ⊗ and header control 22×22, gaps 4 pt (card) / 8 pt (header); symbols share one size and weight (12 pt semibold) across SwiftUI buttons and AppKit pop-ups |
| 9 | Card | Caption contrast on bright pictures | `.secondary` 3.27:1 on a light photo | `.primary` 80% + stronger top scrim: 6.9:1 |
| 10 | Card | Transparent PNG showed the window through | caption 1.95:1 on grey | black base under every thumbnail: 6.9:1 |
| 11 | Card | ⊗ remove button | cross 2.07–2.56:1 on its disc | white cross on a 40% black disc: 14.5:1 |
| 12 | Card | Unreadable files (damaged, MKV) offered ▷ Start and a format pop-up | ▷ + pop-up | ⚠︎ symbol, no tools (also for failed files that can't be retried) |
| 13 | Card | Kind watermark sat under two-line error text | overlapped | hidden when the card has a third line |
| 14 | Card | Status repeated the format beside the format pop-up ("Ready → MP4 (H.264)" next to "MP4 (H.264)") | doubled | "Ready", "Converting 42%" (the started-with target shows only if the pop-up changed since) |
| 15 | Header | ▷ disappeared when nothing was startable; the format pill jumped | 30 pt jump | slot kept (hidden, disabled, hidden from VoiceOver) |
| 16 | Header | Hairline / pill | 1 pt `.separator` stroke; pill radius 7 at 2 pt vertical padding | `hairlineBorder` (1 device pixel); pill fills the row, inset 6/5.5 pt top/bottom, radius 6 |
| 17 | Window | Divider above the status bar | 1 pt (2 px) | `Hairline()` (1 px) |
| 18 | Window | Scrolled: cards showed through the 8 pt gap above a pinned header | visible sliver | headers have no top gap (spacing moved into the stack and each group's last row), so pinned they sit flush under the toolbar; only the system scroll-edge effect shows content there. (An opaque band can't work: macOS 26 tints the window background with the wallpaper, so no semantic colour matches it: `#282828`/`#313536` vs `#2B2E2E`.) |
| 19 | Window | "Scroll to new files" did nothing for files below the fold; arrow keys never scrolled | `scrollTo` couldn't reach cards inside a nested `LazyVGrid` | rows are direct children of the `LazyVStack` (`CardRow`, id = first card); new files and arrow-key moves scroll into view |
| 20 | Window | Subtitle and status bar disagreed | "9 converted · 2 failed" vs "11 finished · 2 failed" | subtitle removed (the status bar has the count; no title jump when it would come and go). Status bar also counts "N stopped" |
| 21 | Status bar | Start appeared/disappeared in manual-start mode, moving the count | 76 pt shift | always present when "start as soon as added" is off, dimmed when nothing is ready |
| 22 | Menus | Select All, Quick Look, Show in Finder disabled while every file was still "Ready" | disabled | enabled; Show in Finder reveals the originals of waiting files |
| 23 | Merge | Offered unreadable files (Broken.mp4, Movie.mkv): "Merge 7 Files" | 7 incl. 2 unreadable | 5 (only files that were read, play over time, aren't animated images) |
| 24 | Trim | Nudge buttons in one row | chevrons 17 pt tall, text 20 pt | all 20 pt (symbols inside `Text`), 24 pt min width |
| 25 | Trim | Range handles' AX role | `unknown` | `slider` with value description "0:00.0" (`accessibilityRepresentation`) |
| 26 | Trim | Sheet padding | 16 pt (merge sheet 20) | 20 pt |
| 27 | Settings | Width | 520 pt (+40 over the standard) | `Metrics.settingsWidth` (480); two subtitles shortened so nothing orphans |
| 28 | Settings › Destination | Explanation as its own row; "clip / 2.mp4" broke across lines; borderless pull-down 5 pt inside the form's edge | separate row | subtitle under "Save new files", no-break space; standard bordered pop-up (3.5 pt, the system's own margin) |
| 29 | Settings › Presets | "Yours" below the fold; no double-click | list 300 pt | 360 pt (built-ins + Yours visible); double-click or Return uses a preset; right-click Use/Rename/Delete |
| 30 | Merge | Failure text | plain `.orange` | `.textOrange` |

Card text contrast after (light window, dark cards): name ~15:1, facts 6.9:1, errors
(`.textOrange` on the scrim) 7.7:1, bar status 8.0:1. Group-header count `.secondary` on the
accent tint 3.85:1 (the system's secondary floor; accepted). Status-bar count 3.95:1 (same).

### Checked and fine

Empty drop window (20 pt margins, DropZone token radius), toolbar (Clear List / Stop All +
Add Files in one glass group), progress / done / settings-changed / stopped / failed cards,
the outdated notice, card and group pop-up menus (native `NSMenu`, subtitles), merge sheet,
Settings › General / About, selection ring (3 pt accent, inside the card edge), window
buttons 16×16, `[unlabeled]`: 0 in the window, trim and merge sheets and every Settings tab.

### Not done / owed

- **Hover, focus ring and real keyboard on the grid:** the owner was active all session
  (HID idle 0–17 s), so no window activation, real pointer or global keys. Arrow-key scrolling
  is in code (see #19) but was only exercised indirectly; hover states are the system's
  borderless-button ones.
- **Alerts** (clear list while converting, quit while converting, rename preset) are stock
  `NSAlert`s; not re-shot.
- **Show in Finder / reveal** wasn't clicked (it activates Finder); code path unchanged
  except #22.
- Once, with the owner active, the main window was gone after an AX menu pick; it didn't
  reproduce in two more tries. Around the same time a dead launchd job entry from one of my
  launches blocked new launches ("Operation already in progress"); I removed that one
  stale entry (`launchctl remove application.app.slopapp.convert.…`) and confirmed normal
  launches work.

### Gates

- `scripts/lint.sh Convert`: pass (was 11 corner + 5 colour failures, 2 warnings).
- `scripts/check.sh Convert --perf`: green. 65 tests in 9 suites. Launch 179 ms, first
  window 383 ms, idle CPU 0.027%, footprint 43.3 MB (busy machine, load 5).
- `scripts/drive tree`: no `[unlabeled]`; close/minimise/zoom 16×16.
- Screenshots (`/tmp/slopapp-polish/convert/`): `after-{light,dark}-01-empty`, `-02-ready`,
  `-03-groups`, `-05-trim-1`, `-07-merge-1`, `-10-settings-{General,Destination,Presets,About}`,
  `after-light-06-selected`, `after-dark-19-scrolled`, `after-13-converting-light`,
  `after-14-converting-dark`, `after-15-outdated-dark`, `after-16-stopped-dark`,
  `after-17-formatmenu-dark-1`; `before-*` for comparison.

### Golden Gate + light/dark (2026-11-06)

Against `docs/design-system.md` §4 "Fitting in on macOS 27 Golden Gate" and §10 items 25–26,
on macOS 27.2. Screenshots in `/tmp/slopapp-polish/convert/gg/` (`sbs-*` are side by side).

**Checked, already fine**
- **Menus are text.** Main menu, card right-click menu and every pull-down's contents
  (formats, quality, size, Save To, presets, group actions, per-file format/sound/turn) are
  plain text (with subtitles and checkmarks). The symbols on the status-bar pop-ups are on the
  button faces, not on menu items.
- **Toolbar is standard.** It's the system `.toolbar`: Clear List/Stop All plus Add Files, in
  the system glass group. The bottom bar is a status bar, not a fake toolbar: no drawn
  background, a hairline above. Toolbar items stay legible over scrolled cards (system
  scroll-edge effect).
- **Glass is the system's.** There's no fake glass. The card bar is `.ultraThinMaterial`
  over a scrim, and its text measures 7.6:1. Group headers use `.bar`.
- **No sidebar** (drop-in window archetype).
- **Hairline (now 1 pt of layout).** Status bar re-measured: hairline at 521–522 pt, Start
  531–551 pt, 9 pt above and below; the + and Start share a centre at 541 pt. Convert uses
  `FileQueue` (the model) but not `FileQueueView`, so the FileQueue view changes don't touch it.

**Changed**

| Item | Before | After |
|---|---|---|
| Card selection ring | accent, always | `selectionRing(activeState)`: accent when the window is key, system grey when not |
| Per-file tool highlight (trim button, sound/turn/format pop-ups) | accent, always (AppKit `contentTintColor`) | `windowAccent`; `BarMenuButton(active:)` tints `secondaryLabelColor` in a background window |
| Progress fill | accent 45% | `windowAccent(activeState)` 45% |
| Group header tint | accent 10% | `windowAccent(activeState)` 10% (neutral when inactive) |
| New-file flash | accent 18% | `selectionTint(activeState, opacity: 0.18)` |
| Presets "in use" ✓ | accent; would vanish on a selected (accent) row | `windowAccent`, and the selected-row text colour on a selected row (`backgroundProminence`) |
| Trim range bar and handle ring | accent | `windowAccent` |
| Card chrome drawn pure black/white: base under thumbnails, scrim, ⊗ disc and cross, hairline, watermark, reduce-transparency bar | `Color.black` / `.white` | `OverlayPalette.ink` / `.paper` (cards sit on arbitrary pictures, so they keep the dark palette in both modes) |
| Card caption contrast after the palette change | 4.48:1 on the brightest photo | 90% label colour: 5.17:1 (other captions 7.5–9.0:1, errors 6.0:1, bar status 7.6:1; identical in light and dark) |
| Trim handle | pure white fill, black shadow | `controlBackgroundColor` (white in light, a dark ring handle in dark), `shadowColor` 35%, tight |
| Trim sheet for sound files | explicit black band behind the player (black in light mode) | removed: AVKit draws its own letterbox for video and its own audio panel |
| Merge list icon column | waveform narrower than film: sound-file names 1.5 pt left of the others | fixed 18 pt column, names on one edge |

**Kept, with reasons**
- **Drop-target outline stays the accent** when the window isn't key. You drag from
  another app, so the window is never key during a drop. Finder's drop targets do the same.
- **The accent gradient behind sound files** isn't greyed. It stands in for the file's
  picture (artwork, like a thumbnail), not a selection or control.

**Live appearance change.** Added `CONVERT_REVIEW=flip`, which switches the app light ↔ dark
4 s after launch. I compared a dark launch flipped to light against a fresh light launch, and
the reverse. Light → dark: 0 px differ. Dark → light: about 5 px (fuzz 3%), only in the title
text. There are no CALayer/CGColor values in Convert. `BarMenuButton`'s colours are dynamic
`NSColor`s and its forced-dark appearance applies only on cards.

**Active and inactive, both modes**
- `sbs-dark-active-inactive.png`: dark, active left, inactive right.
- `light-active-selected-edits.png` (active) and `light-B-selected-behind-settings.png`
  (inactive, Settings in front).
- `sbs-inactive-edits.png`: per-file highlights, light active and dark inactive.
- `sbs-presets.png`: inactive Settings › Presets with a preset in use, light and dark.
- `sbs-trim-sound.png`: sound-file trim sheet, light and dark.
- `sbs-merge.png`: merge sheet, light and dark.

Active shots were taken only after 60 s of no HID input. `scripts/drive launch` itself resets
the HID idle timer, so the gate waits after launching.

**Not done**
- Hover, and real keyboard focus on the grid. As before, this needs the real pointer and keys.

**Gates:** `scripts/check.sh Convert --perf` green: 65 tests, launch 159 ms, first window
351 ms, idle CPU 0.037%, footprint 44.7 MB. `[unlabeled]`: 0. Defaults restored from backup.
