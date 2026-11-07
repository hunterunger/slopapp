# Dictate research (a port of the owner's own Better Transcriber)

> Copied from [`TEMPLATE.md`](TEMPLATE.md) and adapted: Dictate isn't inspired by a Setapp app,
> it's the owner's own menu bar dictation app, **Better Transcriber 1.0.7** (bundle
> `oxen.Better-Transcriber`, Xcode project at `~/OnMyMac/developer/swift/Better Transcriber/`,
> about 4,300 lines of Swift), moved into Slopapp. Studied on 2026-11-07 on macOS 27.2 from its
> source (read-only) and its data locations (names and keys only, never content). The installed
> copy at `/Applications/Better Transcriber.app` is the owner's daily driver: it was never
> launched, quit, reconfigured or driven. Commercial apps in the same space (Superwhisper,
> Wispr Flow) were looked at only for patterns; nothing is copied from them.

## The job

Talk instead of type, anywhere. You hold a key, say a sentence, let go, and the words appear
where the cursor is, in any app, with no cloud and no account. People reach for it dozens of
times a day for messages, notes, prompts, code comments and email. Done feels like: the words
are there a beat after you let go, spelled right, and you never left the app you were in.

The one interaction that matters: **hold Fn → speak (the words run around a ring under the
notch) → release → the text is typed into the focused app.** Everything else (cleanup, history,
models, files) serves that loop or recovers from it.

## Who and when

- Replying to messages and email without typing; dictating notes and to-dos.
- Writing long prompts for AI tools (much faster spoken than typed).
- Rewriting selected text by voice ("make this friendlier", "turn this into a list").
- Transcribing a voice memo or meeting recording dropped into a window.
- Many times a day, a few seconds each. Settings are touched at setup and when a word keeps
  coming out wrong.

## Feature inventory (Better Transcriber 1.0.7 → Dictate)

Status: **done** (in Dictate and walked through), **done+** (done and improved), **deferred**
(with reason), **dropped** (with reason).

| # | Feature in Better Transcriber | How it works there | Dictate | Notes |
|---|---|---|---|---|
| 1 | Global trigger: Fn (Globe) key | `NSEvent` flagsChanged monitors (global needs Accessibility) | done | Same monitor, restarted when Accessibility is granted (it saw nothing until a relaunch before) |
| 2 | Global trigger: custom shortcut | KeyboardShortcuts 2.4, default ⌥Space | done | KeyboardShortcuts 1.10 via SlopKit (`ShortcutRow`). No default: ⌥Space types a no-break space and the default trigger is Fn anyway |
| 3 | Push to talk / toggle | `HotkeyManager` | done+ | Pure `TriggerGesture` (tested). New third mode: hold to talk, quick tap for hands-free. A start the app refuses no longer desyncs toggle mode |
| 4 | Record mic → 16 kHz mono | `AVAudioEngine` tap + `AVAudioConverter` | done | Same, plus: the engine is created per recording (no audio hardware touched at idle), unplugging the mic mid-dictation transcribes what was said |
| 5 | Microphone choice | Core Audio device UIDs | done | Same; an unplugged choice is kept and shown as "Not Connected" |
| 6 | Transcription engines: Parakeet (FluidAudio), Whisper (WhisperKit) | `TranscriptionEngine` protocol | done | `SpeechEngine` protocol in the core, fake in tests |
| 7 | Model catalog: 5 Parakeet + 6 Whisper | `ModelCatalog` | done+ | Same list. Parakeet Mandarin was broken there (a CTC-only model loaded through the TDT path throws); Dictate uses FluidAudio's Mandarin manager in 15 s windows. Sizes corrected from the model repositories (the large Whisper models were shown as 600–950 MB; they're 1.5–3.1 GB) |
| 8 | Model download | Implicit: selecting a model or launching downloads it | done+ | **Explicit**: nothing downloads until you press Download. Progress per model, errors on the row, Move to Trash per model. Whisper's tokenizer comes with the download, so loading never touches the network |
| 9 | Model loading | Loads at launch, kept forever (≈330 MB footprint measured) | done+ | Loaded on demand **while you speak** (≈100 ms from cache), unloaded after 10 min idle by default; "Always" keeps the old behaviour. First use compiles for the Neural Engine once (≈15 s), done during setup |
| 10 | "Model isn't ready" failure | Recording refused until loaded | done+ | Never refused: recording starts at once, the model loads alongside |
| 11 | Live preview | Re-transcribes the whole buffer every 0.9 s | done+ | Last 20 s only (constant cost on long dictations); never triggers a load; can be turned off |
| 12 | Silence / annotations ignored | `[BLANK_AUDIO]`, `(silence)` dropped | done+ | Also `<|nospeech|>`, `*cough*`, leading tags; tested |
| 13 | Too-short taps ignored (< 0.25 s) | | done | |
| 14 | Key released before recording started | `pendingStop` | done | Tested |
| 15 | Filler-word removal | regex + tidy | done+ | Removes the commas around the filler too ("Um, so we" → "So we"); tested against real-word false positives |
| 16 | Word replacements | whole word, case-insensitive | done+ | Also works for terms with symbols ("C#", ".NET") |
| 17 | Lowercase start, no final period | | done+ | Leaves "I" and acronyms alone |
| 18 | AI cleanup (Apple Intelligence) with 4 toggles, vocabulary, custom instruction | FoundationModels | done+ | Same prompts in our words; the session is prewarmed when recording starts so polishing is quicker; stray quotes/"Here is" wrappers stripped |
| 19 | Per-app cleanup overrides | bundle-id rules, Default/On/Off | done | Own Settings tab ("Apps") |
| 20 | "Test cleanup" preview | Settings | done | "Try it" section in Cleanup |
| 21 | Command Mode (rewrite selection by voice) | ⌘C selection, FoundationModels, paste | done | Clear messages for no selection / no Accessibility / no Apple Intelligence. No default shortcut (⌥⌘Space was Finder's search) |
| 22 | Insert text: clipboard + ⌘V, restore clipboard | Restores plain text only | done+ | Restores **every** clipboard type (images, files, rich text), marks its temporary write as transient so clipboard managers skip it, doesn't clobber something copied in between, doesn't block the next dictation |
| 23 | Clipboard-only mode | toggle | done | Shows "Copied to the clipboard" |
| 24 | — | | new | **Type** insertion (keystrokes, clipboard never touched) as an option |
| 25 | No Accessibility → silently clipboard only | | done+ | Says so, with a button to fix it |
| 26 | Start/stop sounds (Tink/Pop) | NSSound | done | Same system sounds |
| 27 | Recording HUD: liquid drop from the notch, transcript around the ring, voice-reactive glow, waveform, ✓/! outcome | Canvas metaballs, spring physics, YIN pitch | done | Ported nearly line for line. Colours now follow the person's accent colour (purple for Command Mode) instead of fixed orange; liquid is true black under a notch (to merge with it), the dark window colour elsewhere; Reduce Motion kept |
| 28 | Menu bar menu: start/stop, transcribe file, status, copy last, settings, setup assistant, updates, quit | | done+ | Text-only Golden Gate menu; adds Cancel, Paste Last Transcript, Open History (⌘Y), a fix-it item when something's wrong; SlopKit `MenuFooter` |
| 29 | Menu bar icon shows state | waveform / mic.fill / badge / triangle | done | mic / mic.fill / waveform / triangle, with VoiceOver labels |
| 30 | File transcription | one file, plain text, Copy | done+ | Window with drop zone, several files queued, audio **and video**, durations, Copy, Save as .txt (⌘S), Open With from Finder |
| 31 | History: save, search, copy, re-insert, delete, clear, "teach a word" | Settings tab, 200 entries | done+ | Own window (library archetype): toolbar search (every word, accents ignored), multi-select, ⌘C, Delete with Undo (⌘Z), Clear with confirmation + Undo, add word to vocabulary. 500 entries. "Insert into focused app" from Settings pasted into Settings itself, so it's replaced by Paste Last Transcript (menu or shortcut) |
| 32 | Onboarding: welcome, mic, accessibility, trigger, done | | done+ | Adds: import from Better Transcriber, the "macOS will ask again" note, a model step with explicit download, a Try It box |
| 33 | Permissions tab | | done | Folded into General (Permissions section) |
| 34 | Launch at login | SMAppService | done | SlopKit toggle |
| 35 | Accessory-app activation tricks for Settings | swaps activation policy | done | SlopKit `AppActivation`/`SettingsWindow` instead |
| 36 | Sparkle auto-update | | dropped | Slopapp apps update through the launcher (owner's call) |
| 37 | `appToneRules` (in the owner's defaults, not in 1.0.7's code) | removed feature | dropped | Not in the current app |
| 38 | — | | new | Esc cancels a dictation (only registered while one is in progress) |
| 39 | — | | new | Password fields (Secure Input) get the text on the clipboard instead of losing it |
| 40 | — | | new | Language choice for Whisper / Parakeet v3 hints | deferred: Better Transcriber didn't have it; needs UI and testing per language |
| 41 | — | | new | Streaming (true real-time) preview with FluidAudio's streaming managers | deferred: the windowed preview is fast enough on the Neural Engine |

## Key flows

### Flow 1: dictate (the main job)
1. Hold Fn (default; or the shortcut). Recording starts at once with the Tink sound; the
   drop falls from the notch and opens into the ring.
2. The model loads in parallel if it isn't in memory (≈100 ms).
3. Words appear around the rim every 0.9 s.
4. Release: Pop sound, the ring pulses while transcribing (≈0.1 s for a sentence on Parakeet
   v3), then polishing if AI cleanup is on.
5. The text is pasted into the app that was in front when you started; the clipboard is put
   back half a second later. The ring shows ✓ and retracts into the notch.
6. Esc at any point before the text goes in cancels everything.

### Flow 2: first run (switching from Better Transcriber)
1. Setup Assistant opens. Welcome says Better Transcriber is on this Mac and offers
   **Bring Them Over**. One click copies settings (same keys), shortcuts, history and clones
   the Parakeet model folders (APFS clones: no extra disk, originals untouched).
2. It says macOS will ask again for Microphone and Accessibility, and offers to quit Better
   Transcriber so one Fn press doesn't dictate twice.
3. Microphone → Accessibility (SlopKit `PermissionGate`, updates by itself) → the model step
   shows "Parakeet TDT v3 Is Ready" (imported) or a Download button → trigger and behaviour →
   Try It box.

### Flow 3: Command Mode
Select text → hold the Command Mode shortcut → say "make this more formal" → release → the
selection is replaced by Apple Intelligence's rewrite. Needs Accessibility and Apple
Intelligence; each missing piece gets its own message.

### Flow 4: transcribe files
Menu › Transcribe Audio Files… (⌘O) or drop files on the window (or Open With › Dictate).
Files run one after another; select one to read, copy or save its transcript.

## Settings inventory

| Setting | Default | Options | Notes |
|---|---|---|---|
| Launch at login | off | | SlopKit |
| Show in menu bar | on | | SlopKit; reopening the app brings it back |
| Microphone | System Default | input devices | |
| Type into the app you're using | on | | off = clipboard only |
| Insert by | Paste | Paste, Type | new |
| Play sounds | on | | |
| Show words as you speak | on | | new toggle |
| Keep a history | on | | |
| Start dictation with | Fn key | Fn, shortcut | |
| Dictation shortcut | none | | shown when "shortcut" is chosen |
| Behaviour | Hold to talk | Hold, Press/press, Hold or tap | third mode new |
| Command Mode shortcut | none | | |
| Paste last transcript shortcut | none | | new |
| Model | Parakeet TDT v3 | 11 models | download explicit |
| Keep the model in memory | 10 min after use | Always, 1 hour, 10 min | new |
| Remove filler words | off | | |
| Lowercase start, no final period | off | | |
| Word replacements | none | | |
| AI cleanup + 4 options + vocabulary + extra instruction | off / on×4 | | |
| Per-app overrides | none | | |

## Menus and shortcuts

Status item menu: status line · fix-it item (when needed) · Start/Stop Dictation · Cancel
Dictation (while busy) · Transcribe Audio Files… ⌘O · Copy / Paste Last Transcript · Open
History ⌘Y · Setup Assistant… · Settings… ⌘, · About Dictate · Quit Dictate ⌘Q.
Global: Fn or the dictation shortcut; Command Mode and Paste Last Transcript shortcuts (unset
by default); Esc while dictating.

## Permissions and system integration

- **Microphone** (`NSMicrophoneUsageDescription`, `com.apple.security.device.audio-input`
  entitlement under the hardened runtime). Asked on the first dictation or in setup. Denied →
  a message with the System Settings link; nothing records.
- **Accessibility**: typing/pasting into other apps, the global Fn monitor, Command Mode's
  ⌘C. Without it, text is copied and a message says how to allow typing.
- Apple Intelligence (optional) for AI cleanup and Command Mode; unavailable → toggles disabled
  with the reason.
- Document types: audio and movie files at `LSHandlerRank` Alternate (Open With only, never a
  default).
- Not sandboxed (synthetic keys, global monitors), hardened runtime on.

## Where things live, and the import

| What | Better Transcriber | Dictate |
|---|---|---|
| Settings | defaults `oxen.Better-Transcriber` | defaults `app.slopapp.dictate` (same key names) |
| Shortcuts | `KeyboardShortcuts_record`, `_commandMode` in its defaults | same names in Dictate's defaults |
| History | `~/Library/Application Support/oxen.Better-Transcriber/history.json` | `~/Library/Application Support/app.slopapp.dictate/history.json` (same JSON) |
| Parakeet models | `~/Library/Application Support/FluidAudio/Models/<model>` (FluidAudio's shared folder) | `~/Library/Application Support/app.slopapp.dictate/Models/FluidAudio/<model>` |
| Whisper models | `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<model>` | `…/app.slopapp.dictate/Models/WhisperKit/models/argmaxinc/whisperkit-coreml/<model>` |
| Neural Engine compile cache | `~/Library/Caches/oxen.Better-Transcriber` | `~/Library/Caches/app.slopapp.dictate` (rebuilt once, ≈15 s) |

Why Dictate doesn't simply point at FluidAudio's shared folder: FluidAudio deletes and
re-downloads a model folder when a load fails. Pointing at the shared folder would let Dictate
modify Better Transcriber's (and other apps') copy. A clone costs no disk (APFS shares the
blocks until one side changes) and keeps the originals untouched. Across volumes (not APFS) it
falls back to a normal copy. Whisper models live in Documents, which macOS guards, so Dictate
only looks there when Better Transcriber was set to Whisper.

The import is offered in the setup assistant and runs only when clicked, so a test launch
never imports stale data. It never overwrites a value Dictate already has, and it records that
it ran (once only).

## UX patterns worth adopting (from the space, in our words)

- Start recording the instant the key goes down; do slow things (loading, AI warm-up) in
  parallel, never before.
- A visible, cancelable state: Esc always gets you out.
- Hands-free toggle without giving up hold-to-talk.
- Be explicit about the network: on-device apps earn trust by saying when they download.

## What we won't copy, and what we'll do better

- Not copying: names, icons, copy or visuals from Superwhisper or Wispr Flow. The ring and
  icon are the owner's own work, carried over.
- Better than Better Transcriber: see the done+ rows: model downloads only on request, lower
  idle memory, no "model not ready" refusals, clipboard fully restored, Esc to cancel,
  multi-file and video transcription, a real history window with Undo, working Mandarin.

## Edge cases

Covered by tests or the walkthrough: key released before recording starts; second start while
busy; silence and annotation-only transcripts; a 1000-sample tap; load failure; microphone
denied / undetermined; no model installed; Apple Intelligence unavailable; Command Mode with no
selection or no Accessibility; Esc while recording and while transcribing; clipboard-only;
history off; unknown stored model ids (fall back to defaults); old per-app rules missing fields;
unreadable legacy history; Intel Macs (Parakeet hidden behind "Needs Apple silicon"); a non-audio
file; a silent file; a mic unplugged mid-dictation (transcribes what it has); password fields.
Not testable here without a human: real speech through a real microphone, the Fn key itself.

## Our v1 scope

- [x] Fn / shortcut trigger with hold, toggle and hold-or-tap
- [x] Record, live preview, transcribe on-device (Parakeet, Whisper), insert into the focused app
- [x] Rule cleanup (fillers, replacements, lowercase) and AI cleanup with options
- [x] Per-app overrides
- [x] Command Mode
- [x] Recording ring (notch drop) with outcome
- [x] Explicit model download, choice, removal, memory policy
- [x] File transcription (drop, choose, Open With)
- [x] History window (search, copy, delete/undo, teach a word)
- [x] Setup assistant with import from Better Transcriber
- [x] Settings: General, Shortcuts, Models, Cleanup, Apps, About
- [x] Esc cancels, Paste Last Transcript

## Decisions made (owner asleep; recorded here)

| Question | Decision | Why |
|---|---|---|
| Keep the model loaded all the time? | No: load while you speak, unload after 10 min idle (setting offers Always) | Warm load is ≈100 ms and overlaps speech; the always-loaded model cost ≈330 MB all day and fails the 50 MB menu bar budget |
| Point at FluidAudio's shared model folder or clone? | Clone | FluidAudio deletes and re-downloads a folder whose load fails; a clone keeps the old app's files safe at no disk cost |
| When does the import run? | On "Bring Them Over" in setup | Explicit, and a test/perf launch never imports a stale snapshot |
| Default shortcuts | None (Fn is the trigger) | ⌥Space types a no-break space; ⌥⌘Space is Finder search |
| Default behaviour | Hold to talk (unchanged) | The owner's current setting; hold-or-tap is opt-in |
| History in Settings or its own window? | Own window | Library archetype; Settings tabs stay short |
| Insertion | Paste stays default, Type added | Paste is proven in daily use; Type helps people who don't want the clipboard touched |
| Ring colours | Accent colour (purple for Command Mode), system green/yellow outcome | Design system: the user's accent, no hardcoded colours |
| Dependency versions | The owner's proven set: argmax-oss-swift 0.18.0, FluidAudio 0.14.8 | Same model folder names (zero re-download) and known-good behaviour; newer releases exist (1.1.1, 0.18.2) and are a later upgrade |
| Sparkle | Dropped | Slopapp's launcher updates apps |

## Open questions

- Upgrade argmax-oss-swift to 1.x and FluidAudio to 0.18.x (check folder names stay the same).
- A language picker for multilingual models.

## Sources

- Better Transcriber source and `AGENTS.md` (owner's repo, read-only).
- FluidAudio and argmax-oss-swift sources at the pinned versions.
- Comparisons used for patterns only: [Spokenly: Superwhisper vs Wispr Flow](https://spokenly.app/blog/superwhisper-vs-wispr-flow),
  [Zack Proser: WisprFlow vs Superwhisper](https://zackproser.com/blog/wisprflow-vs-superwhisper),
  [Willow: Superwhisper vs Wispr Flow](https://willowvoice.com/blog/super-whisper-vs-wispr-flow-comparison-reviews-and-alternatives).

## Build notes

Built 2026-11-07 on macOS 27.2 (M4 Max), Swift 6.4, SDK 27.0. Release build is universal
(arm64 + x86_64), 34 MB.

**Structure.** `DictateCore` (no UI): `Preferences` (settings, same keys as Better Transcriber),
`ModelCatalog`, `TextCleanup`/`Vocabulary`, `AICleanup` (prompts + `TranscriptProcessor`),
`TriggerGesture`, `History`, `LegacyImport` (+ `FileCloner`), `ModelHost`,
`DictationController`, `AudioFeatures` (ported DSP), `AudioDecoder`. System seams are
protocols (`SpeechEngine`, `AudioCapturing`, `MicrophoneAuthorizing`, `TextDelivering`,
`AITextService`, `DictationFeedback`, `HistoryPersistence`, `FolderCloning`, `KeyValueStore`)
with fakes in the tests. The app target uses `.defaultIsolation(MainActor.self)`; realtime
audio (`AudioSink`), WhisperKit (`WhisperPipe`) and `Diagnostics` are explicitly `nonisolated`.

**Gates.**

| Gate | Result |
|---|---|
| `scripts/test.sh Dictate` | 86 tests in 11 suites pass (0.2 s) |
| `scripts/check.sh Dictate --perf` | lint, tests, universal release bundle, smoke, perf, catalog: all PASS |
| `scripts/perf.sh Dictate` | Final run, first launch with the setup assistant open: launch 162 ms (< 300), first window 382 ms (< 600), idle CPU 0.008 % (< 0.2), footprint 36.0 MB (< 50); load 13 (busy machine). Earlier run with no window: 147 ms, 317 ms, 0.004 %, 23.2 MB |
| `scripts/drive tree` | 0 `[unlabeled]` in the setup assistant (every step), all six Settings tabs, History, Transcribe Audio Files and the status item menu |
| Network | Both engines load and transcribe under a sandbox profile that denies all outbound IP: no network outside explicit downloads |

**Real engines, synthetic speech** (`say -o` AIFF files, `DICTATE_TRANSCRIBE` headless mode):

| Model | First load (Neural Engine compile) | Warm load | 6.2 s of speech |
|---|---|---|---|
| Parakeet TDT v3 (cloned from the owner's FluidAudio folder) | 14.5 s | ≈100 ms | 94–107 ms |
| Parakeet TDT-CTC 110M (downloaded by Dictate, 319 MB) | 20.4 s | 96 ms | 46 ms |
| Whisper Tiny (downloaded by Dictate, 76 MB incl. tokenizer) | 3.8 s | 170 ms | 99–105 ms (621 ms the first time) |

Transcripts were exact ("Hello, this is a test of the new dictation app, um, the quick brown fox
jumps over the lazy dog."); with filler removal on: "…app, the quick brown fox…" (Parakeet) and
"…app. The quick brown fox…" (Whisper). The old app kept v3 loaded at ≈330 MB footprint all
day; Dictate idles at 23 MB and reloads in ≈100 ms while you speak.

**Import** (setup assistant, test mode, synthetic legacy prefs and history, the owner's real
FluidAudio model folder as a read-only source): 10 settings, 4 dictations, Parakeet v3 + v2
brought over. A fresh clone of the 904 MB model tree changed free disk space by 1 MB; the
originals' modification times were unchanged; nothing was written to `oxen.Better-Transcriber`.

**Walkthrough** (release build, `DICTATE_FAKE_AUDIO` playing the synthetic file in real time,
test hooks, `DICTATE_TEST_QUIET` so windows never took focus; light and dark screenshots in
`/tmp/dictate-test/shots`): setup assistant (welcome, import, microphone, Accessibility not
granted path, model ready, trigger, try it); dictation start → ring with live words around the
rim → stop → transcript saved to history (front app recorded) → no Accessibility, so it was
copied to the private test pasteboard with a message; Esc-cancel mid-recording (nothing saved);
Command Mode with Apple Intelligence unavailable (clear message); Settings tabs; History;
Transcribe Audio Files with two files queued; Whisper and Parakeet downloads through the
download hook into Dictate's folder (FluidAudio's shared folder untouched). Status item menu
opened (owner idle ≥ 60 s): status line, fix-it item for a missing model, every command and
shortcut present. **Real insertion**: launched with `--direct` (Accessibility), a throwaway
AppKit test window in front, `DICTATE_INSERT_ONLY_INTO` locking insertion to it: the fake
recording was transcribed and typed into the window ("insert typed chars=92", text matched).
Twice another builder's app came to the front mid-test and the lock correctly refused to type.

**Not exercised for real, and why.**
- AI cleanup and Command Mode with a live model: this Mac's Apple Intelligence reports
  `modelNotReady`. The pipeline, prompts and reply cleanup are covered by fake-backed tests;
  the unavailable path was walked through.
- Real microphone and the physical Fn key: by rule (never record the owner's voice or room; no
  global keys). `TriggerGesture` is unit-tested; the recorder shares its tap/resample code with
  the owner's daily-driver app.
- The paste path against the real clipboard: by rule (never read the owner's clipboard). The
  snapshot/restore is unit-tested on private named pasteboards (every item and type survives,
  transient markers set); the ⌘V itself is the same event code as the tested typing path, with
  a layout-aware key.
- Mandarin, Japanese and the large Whisper models: not downloaded (600 MB to 3 GB each); they
  go through the same engine code as the models that were tested.

**Bugs found and fixed during testing.**
- Quitting the app with the setup assistant open marked it "done" (SwiftUI closes windows on
  quit), which would have hidden the import offer on the owner's real first launch. Now only a
  person closing it counts (`applicationShouldTerminate` sets a flag first).
- Smoke tests run the binary as a child of the terminal and can inherit its Accessibility and
  microphone grants: Dictate now never installs its triggers under `SLOPAPP_SMOKE_TEST`.
- The 110M model needs a second folder (`parakeet-ctc-110m-coreml`); the import clones it too.
- ⌘V/⌘C now follow the keyboard layout (Dvorak, AZERTY), as in Clips.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
