# Convert

Drop in audio, video or images and convert them.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Permute.

**Status:** alpha

## What it does

Drop videos, audio files, images or whole folders on the window (or the Dock icon, use
**Choose Files…** ⌘O, or copy files in Finder and press ⌘V). Conversion starts straight
away. Each kind of file has its own target, shown in the bar at the bottom, so a mixed drop
does the right thing for every file:

| Kind | Targets (default first) |
|---|---|
| Video | **MP4 (H.264)**, MP4 (HEVC), MOV (ProRes 422), GIF, Audio Only (M4A), Audio Only (WAV) |
| Audio | **M4A (AAC)**, Apple Lossless (M4A), WAV, AIFF |
| Image | **JPEG**, PNG, HEIC, AVIF, TIFF |

HEVC, ProRes and AVIF only appear on Macs that can write them. Animated GIFs (and animated
PNG, WebP or HEIC) count as videos: they become MP4s with the Video target.

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
- Videos with several sound tracks get them mixed into one; surround sound becomes stereo.

No permissions needed. No network access, no accounts, no tracking.

## Keyboard

| Action | Shortcut |
|---|---|
| Choose Files… | ⌘O |
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

Every format, size and Save To choice is also in the **Format** menu.

**Settings › General:** Play sound when done (on), Keep original file dates (off). There's no
Launch at login: Convert is a window you open when you have files.

## Not there yet

Trim, merge/stitch, a target file size ("under 25 MB"), FLAC output, Finder Quick Action,
Shortcuts action, Drop Zones, video to image sequence, rotate, a remove-location option,
progress on the Dock icon.

## Develop

```sh
scripts/test.sh Convert     # unit tests (real conversions of synthetic media)
scripts/run.sh Convert      # build a debug .app and open it
scripts/check.sh Convert    # the full gate: tests, release bundle, launch smoke test

# Synthetic test media (moving test pattern + tones, images, files it should refuse):
swift run --package-path apps/Convert ConvertFixturesTool /tmp/convert-test/fixtures [--quick]
```

Logic lives in `Sources/ConvertCore` (tested): `Planner` decides copy vs re-encode per track,
`Transcoder` streams AVAssetReader → AVAssetWriter, `GIFStreamWriter` writes GIFs frame by
frame (flat memory, only changed pixels stored), `ImageConverter` uses ImageIO. Views and
wiring live in `Sources/Convert`, on SlopKit's `FileQueue`.

For screenshots: `CONVERT_APPEARANCE=light|dark`. Scripted tests can point ⌘C/⌘V at a
private pasteboard with `CONVERT_PASTEBOARD=<name>` so the real clipboard is never touched.
