# Dictate

Talk, and your words appear wherever you're typing.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Superwhisper and Wispr Flow.

**Status:** stable (1.0.0). Needs macOS 26.4 or later (on-device AI cleanup and the speech engines).

## What it does

Hold the **Fn** key (or a shortcut you choose), speak, let go. Your words are turned into text
**on your Mac** and typed into the app you're using. While you talk, the words run around a
small ring that drops out of the notch.

- **Two speech engines, all local:** Parakeet (fastest, on the Neural Engine of Apple silicon
  Macs) and Whisper (every Mac, many languages). Pick a model in Settings › Models.
- **Cleanup:** remove filler words, fix names you define ("Katie" → "Kaity"), lowercase-start
  mode, and optional polishing with Apple Intelligence (self-corrections, lists, punctuation,
  your vocabulary), with different rules per app if you like.
- **Command Mode:** select text, hold your Command Mode shortcut and say an edit ("make this
  friendlier", "translate to Spanish"). Uses Apple Intelligence on the Mac.
- **Files:** drop audio or video files on the Transcribe window (or Open With › Dictate) to get
  a transcript to copy, or save as plain text or subtitles (SRT, WebVTT) timed from the words.
- **No menu bar icon needed:** while one of Dictate's windows is in front, the **Dictation**
  menu has everything the icon's menu has. A full menu bar can hide the icon (next to the
  camera notch above all); Dictate notices, says so in Settings › General, and opening Dictate
  again (Finder, Spotlight) always brings up Settings.
- **History** of dictations, searchable, with Undo. **Esc** cancels a dictation.
- **Moving from Better Transcriber:** the setup assistant offers to bring over its settings,
  shortcuts, history and downloaded models (cloned, so they take no extra space, and the
  originals stay untouched). macOS asks again for Microphone and Accessibility because Dictate
  is a new app.

## Network: model downloads only

Dictate makes **no network connections** except one you start yourself: downloading a speech
model (from Hugging Face, ≈80 MB to ≈3 GB, once per model) in the setup assistant or
Settings › Models. Transcription, cleanup and Command Mode run on the Mac. No analytics, no
accounts. Models live in `~/Library/Application Support/app.slopapp.dictate/Models`.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| Microphone | To hear you | Nothing records; Dictate says how to allow it |
| Accessibility | To type into other apps, notice the Fn key, read the selection for Command Mode | Text is copied instead, and Dictate tells you |

Tip: set **System Settings › Keyboard › Press 🌐 key to: Do Nothing**, so Fn doesn't also open
the emoji picker.

## Shortcuts

| Shortcut | What |
|---|---|
| Fn (hold) | Dictate (default; or your own shortcut) |
| Esc | Cancel the dictation in progress |
| Command Mode shortcut | Rewrite the selection by voice (set it in Settings › Shortcuts) |
| Paste last transcript shortcut | Type your last dictation again (optional) |
| ⌘O, ⌘Y, ⌘, (in the menus) | Transcribe files, history, Settings |
| ⌘S, Delete (Transcribe window) | Save the transcript (text or subtitles), remove files from the list |
| Esc (setup assistant) | Close it |

## Not there yet

- A language picker for multilingual models (they detect or default as their libraries do).
- True streaming recognition (the live preview re-reads the last 20 seconds every 0.9 s).
- Updating argmax-oss-swift / FluidAudio to their newest majors.
- Subtitles from the Mandarin model are spread evenly over the audio (it reports no word
  timings); Whisper's word timings are untested on this build's test Mac.
- Shortcut recorders read as search fields to VoiceOver (the shared recorder control).

## Develop

```sh
scripts/test.sh Dictate     # unit tests (core logic, fakes for audio, engines, insertion, AI)
scripts/run.sh Dictate      # build a debug .app and open it
scripts/check.sh Dictate    # the full gate: lint, tests, release bundle, smoke test
```

Logic lives in `Sources/DictateCore` (tested): settings, the cleanup pipeline and prompts,
`ModelHost` (download/load/unload/one-at-a-time), `DictationController` (record → transcribe →
clean up → insert, Command Mode, Esc), `TriggerGesture`, history, the import, audio features
and file decoding. `Sources/Dictate` has the views and the real system pieces: `AudioRecorder`,
the Parakeet and Whisper engines, Apple Intelligence, `TextInserter`, hotkeys, the recording
ring, windows and Settings.

### Test hooks

Scripted tests never touch real settings, history, models, the clipboard or other apps. See
`Sources/Dictate/Diagnostics.swift`: `DICTATE_DATA_DIR`, `DICTATE_MODELS_DIR`,
`DICTATE_FAKE_AUDIO` (play a file instead of the microphone), `DICTATE_INSERT_ONLY_INTO`,
`DICTATE_PASTEBOARD`, `DICTATE_NO_HOTKEY`, `DICTATE_TEST_HOOKS`, `DICTATE_TEST_QUIET`, `DICTATE_TRANSCRIBE`,
`DICTATE_LEGACY_*` (a fake previous install to import from).

Keyboard shortcuts, window positions and the menu bar icon's place always live in the app's own
defaults domain, which a copy of `build/Dictate.app` shares with an installed Dictate. When one
is installed, test with `apps/Dictate/test-copy.sh`: it makes `/tmp/dictate-test/Dictate Test.app`
with its own bundle id (`app.slopapp.dictate.test`), so nothing is shared. Test copies never
change login items.

Design follows [`docs/design-system.md`](../../docs/design-system.md). The app icon is the house
herbarium icon (`Icon.py`, generating `AppIcon.icon`; see `brand/ICONS.md`).
