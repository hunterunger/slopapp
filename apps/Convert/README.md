# Convert

Drop in audio, video or images and convert them.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Permute.

**Status:** alpha

## What it does

Drop videos, audio files, images or whole folders on the window (or the Dock icon, use
**Choose Files…** ⌘O, or copy files in Finder and press ⌘V). Files are sorted into groups
by kind (**Video**, **Audio**, **Images**), each under a header with the group's format. Every
file is a wide card showing its picture, its facts ("1280×720 · HEVC · 30 fps · AAC · Stereo
· 0:41") and a bar along the bottom with its progress and its own tools. Conversion starts
straight away (or, with **Settings › General › Start converting as soon as files are added**
turned off, when you press **Start** ⌘↩, on a card, a group header or the status bar), so a
mixed drop does the right thing for every file:

| Kind | Targets (default first) |
|---|---|
| Video | **MP4 (H.264)**, MP4 (HEVC), MOV (ProRes 422), GIF, Audio Only (M4A), Audio Only (WAV) |
| Audio | **M4A (AAC)**, Apple Lossless (M4A), WAV, AIFF |
| Image | **JPEG**, PNG, HEIC, AVIF, TIFF |

HEVC, ProRes and AVIF only appear on Macs that can write them. Animated GIFs (and animated
PNG, WebP or HEIC) count as videos: they become MP4s with the Video target.

- **Each file can have its own settings**, from the tools on its card (or the **Edit File**
  menu, for every selected card at once):
  - **Format**: anything its group offers, instead of the group's format.
  - **Trim** (⌘T): a player with a start/end bar; nudge either end by 0.1 s or 1 s, or set
    it to the playhead with **I** and **O**. Copies stay copies: trimming an H.264 `.mov` to
    `.mp4` doesn't re-encode it.
  - **Rotate and flip** (⌥⌘R, ⌥⌘L): turning a video only changes how it's shown, so it's
    lossless and instant; mirroring redraws the picture. Photos are redrawn upright.
  - **Sound**: keep all tracks mixed (the default), pick one track, or remove the sound.
  Change a finished file's settings and it converts again.
- **Merge** (⇧⌘M, or a group's ⋯ menu): videos (or sound files) end to end into one file, in
  the order you set. Clips of another shape are fitted with black bars. Named "First Clip
  Merged.mp4".
- **Presets** in the status bar: one click sets every format, quality and size, for a device
  (iPhone & iPad, Apple TV 4K, Older Devices & Windows) or a job (Web & Email, Chat GIF,
  Video Editing). **Save Current Settings as Preset…** keeps your own; rename, reorder and
  delete them in **Settings › Presets**.
- **When done** (Settings › General): play a sound (on), remove finished files from the list,
  move originals to the Trash (only once the new file is saved), quit Convert.
- **New files, never overwritten.** `clip.mov` becomes `clip.mp4` next to it (or in a folder
  you pick under Save To). If that name is taken, it's `clip 2.mp4`. The original is never
  touched. The only file Convert ever replaces is one it made itself for the same row in
  this session: **Convert Again** updates `clip.mp4` instead of adding `clip 2.mp4`. Files are written somewhere private first and only appear when they're complete,
  so a stopped or failed conversion leaves nothing behind.
- **No needless re-encoding.** If only the container changes (an H.264 `.mov` to `.mp4`, AAC
  audio to `.m4a`) the video and sound are copied as they are: instant, and no quality loss.
  The row says "No quality loss". A file that's already in the target format is left alone.
  **Smaller** always re-encodes, to make it smaller.
- **Convert Again** (⌘R): change a format, quality or size and a note under the list says
  how many finished files used other settings; Convert Again redoes just those. With rows
  selected it redoes exactly the selection ("Convert Selected Again").
- **Honest sizes:** when a file comes out bigger than the original, the row says so and why
  ("Bigger than the original: H.264 needs more space than HEVC. Choose MP4 (HEVC) to stay
  small").
- **Media facts on every row:** codec, size and length before ("HEVC · 3840×2160 · 1:00 →
  MP4 (H.264)"), and what it became after, with before → after file sizes.
- **Keeps what matters:** rotation (phone videos stay upright), metadata (title, date,
  location), photo orientation, camera details and HDR gain maps of iPhone photos. HDR video
  stays HDR in HEVC and ProRes; for H.264 it's converted to standard range (the row says so).
- **Long jobs:** videos run one or two at a time (images many at once), the Mac won't
  idle-sleep while anything is converting, and when a long batch finishes you get the system
  sound and, if you're in another app, one Dock bounce.

### Quality

| | Video (H.264/HEVC quality) | AAC audio, constant bit rate (stereo / mono) | JPEG | HEIC / AVIF | GIF |
|---|---|---|---|---|---|
| Smaller | 0.40 | 96 / 48 kbps | 70% | 60% | 480 px, 10 fps |
| **Balanced** | 0.55 | 160 / 80 kbps | 85% | 78% | 640 px, 12 fps |
| Best | 0.75 | 256 / 128 kbps | 95% | 92% | 800 px, 15 fps |

GIF sizes are the long edge (640 px wide for landscape clips, 640 px tall for portrait).
GIFs longer than 30 seconds still convert, with a note that long GIFs get big. Lossless
targets (ProRes, WAV, AIFF, Apple Lossless, PNG, TIFF) ignore Quality.

**Size** (Original Size, or up to 4K / 1080p / 720p / 480p) shrinks videos and images to fit,
either way round. Nothing is ever enlarged. H.264 can't go above 4096×2304, so bigger videos
are scaled to fit and the row says so (choose HEVC to keep the full size).

### What it can't do (and why)

Convert uses only what macOS has built in (AVFoundation, ImageIO, VideoToolbox). No FFmpeg,
no downloads, no network.

- **No MP3 output.** macOS can play MP3 but has no MP3 encoder. M4A (AAC) is smaller at the
  same quality and plays everywhere MP3 does, including Windows, Android and browsers.
  If you need MP3 specifically, use a tool that bundles an MP3 encoder.
- **No WebP output.** macOS can read WebP images (so you can convert WebP *to* JPEG, PNG,
  HEIC…) but can't write them. AVIF is the modern small format we can write.
- **Can't read** MKV, WebM, WMV/WMA, FLV, Ogg, DivX/Xvid AVI or VP9: macOS has no reader for
  them. Those rows say so; HandBrake or FFmpeg can convert them.
- Videos with several sound tracks get them mixed into one unless you pick a track; surround
  sound becomes stereo.
- **Subtitles** aren't carried over or burned in, and there's no crop yet.

No permissions needed. No network access, no accounts, no tracking.

## Keyboard

| Action | Shortcut |
|---|---|
| Choose Files… | ⌘O |
| Start (files waiting for Start, or whose settings changed) | ⌘↩ |
| Trim… | ⌘T |
| Rotate Right / Left | ⌥⌘R / ⌥⌘L |
| Merge Selected Files… | ⇧⌘M |
| Move between cards (⇧ to extend the selection) | Arrow keys |
| Paste copied files | ⌘V |
| Copy converted files (to paste in Finder, Mail, chats) | ⌘C |
| Show in Finder (selection, or all results) | ⇧⌘R |
| Quick Look | Space or ⌘Y |
| Convert Again (selection, or files whose settings changed) | ⌘R |
| Stop All | ⌘. |
| Remove from List | Delete |
| Clear List (asks first while converting) | ⇧⌘⌫ |
| Undo / Redo Remove or Clear List (rows come back as they were; nothing is converted again) | ⌘Z / ⇧⌘Z |
| Show the window (Window ▸ Convert) | ⌘0 |
| Select All | ⌘A |
| Smaller / Balanced / Best | ⌘1 – ⌘3 |
| Settings | ⌘, |

Every format, size, preset and Save To choice is also in the **Format** menu.

**Settings:** **General** (start as soon as files are added; when done: sound, remove finished,
move originals to the Trash, quit), **Destination** (Save To, keep original file dates),
**Presets**, **About**. There's no Launch at login: Convert is a window you open when you have
files.

## Not there yet

Crop, subtitles (keep, choose, burn in), watch folders, a target file size ("under 25 MB"),
speed and volume, Drop Zones, video to image sequence, splitting, metadata editing, FLAC
output, Finder Quick Action, Shortcuts action, a remove-location option, progress on the
Dock icon.

## Develop

```sh
scripts/test.sh Convert     # unit tests (real conversions of synthetic media)
CI=true scripts/test.sh Convert   # skips the video/HEIC encodes (CI runners have no media engine)
scripts/run.sh Convert      # build a debug .app and open it
scripts/check.sh Convert    # the full gate: tests, release bundle, launch smoke test

# Synthetic test media (moving test pattern + tones, images, files it should refuse):
swift run --package-path apps/Convert ConvertFixturesTool /tmp/convert-test/fixtures [--quick]
```

Logic lives in `Sources/ConvertCore` (tested): `Planner` decides copy vs re-encode per track,
`Transcoder` streams AVAssetReader → AVAssetWriter, `GIFStreamWriter` writes GIFs frame by
frame (flat memory, only changed pixels stored), `ImageConverter` uses ImageIO. Views and
wiring live in `Sources/Convert`, on SlopKit's `FileQueue`.

For screenshots: `CONVERT_APPEARANCE=light|dark`; `CONVERT_SNAPSHOT=<folder>` makes the app
save a PNG of each of its own windows there every 2 s, and `CONVERT_REVIEW=trim|merge|settings|edits`
opens that view (or applies sample per-file settings) once files are in (for reviews when the screen can't be
captured). Scripted tests can point ⌘C/⌘V at a
private pasteboard with `CONVERT_PASTEBOARD=<name>` so the real clipboard is never touched.
