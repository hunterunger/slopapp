# Shorthand

Type a few letters, get the whole thing.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to TextExpander and Rocket Typist.

**Status:** alpha

## What it does

Shorthand lives in the menu bar. Give a snippet an abbreviation such as `;addr`, and
whenever you type it, in any app, it's replaced by the whole text the moment you type its
last letter.

- **Short, single-line snippets are typed** and leave your clipboard alone. Longer ones,
  and anything with several lines or a tab, are **pasted**, then your clipboard is put back
  exactly as it was (images, files and rich text included). Clipboard managers such as
  Clips skip the borrowed copy. Settings › Advanced can make it always type or always paste.
- **Placeholders** from the Insert Placeholder menu: today's date and the time in your
  formats (short, medium, long, full, ISO), offsets (`{date:+1w}`), custom patterns
  (`{date:format=EEE d MMM}`), the clipboard's text (`{clipboard}`) and where the caret
  should end up (`{cursor}`). Write `{{` or `}}` for a literal brace.
- **Fill-ins**: text fields (`{field:Name}`, `{field:City=Oslo}` with a default), choices
  (`{choice:Tone|Talk soon|Best wishes}`, the first is preselected) and optional sections
  (`{optional:P.S.}…{/optional}`, on unless written `=off`). When such a snippet expands, a
  small form opens next to where you're typing: Tab moves, ↑↓ or a letter changes a choice,
  Space ticks a section, Return inserts, Esc cancels and leaves the abbreviation as typed.
  A name used twice is filled once. If another app comes forward meanwhile, nothing is
  typed: the text is copied instead. What you fill in is never stored.
- **Formatted snippets** (Format › Formatted text): fonts, bold, italic, underline, colours,
  links and images (paste, drop or Insert Image…), for signatures with a logo. They're
  pasted as rich text where the app takes it (Mail, Pages, Notes, browsers, Slack) and as
  plain text where it doesn't (terminals, code editors). Placeholders inside keep the
  formatting they're written in.
- **Snippets inside snippets**: `{snippet:;sig}` puts another snippet's text there, fill-ins
  and formatting included. A group that's turned off is a good home for parts that
  shouldn't expand on their own. A snippet that would include itself is caught and the
  editor says so.
- **Insert a Snippet…** (menu bar, or a shortcut you set in Settings › Shortcuts): a search
  panel over every snippet, most used first. ↑↓ choose, Return inserts it where you were
  typing (fill-ins still ask), ⌘1–9 insert one of the first nine, ⌘C copies, Esc clears,
  then closes. Snippets without an abbreviation live here too. Without Accessibility, it
  copies instead.
- **Only at the start of a word** (on by default), so `sig` doesn't fire inside "design".
- **Exact case** by default; a snippet can **adapt to how it's typed** (`Addr` capitalises
  the text, `ADDR` puts it in capitals).
- **Keys you type while a snippet goes in** are kept, in order, after it.
- **Backspace right after** a typed expansion puts the abbreviation back.
- **Library window**: groups (each can be turned off), search across abbreviation, name and
  text (ignores case and accents), a live preview, conflict warnings as you type, and a
  "Try It" field that works without any permission. Changes save as you type.
- **Import** (File › Import Snippets…): this Mac's Text Replacements, or drop a file:
  TextExpander group files (`.textexpander`), espanso match files (`.yml`), the file System
  Settings makes when you drag rows out of Keyboard › Text Replacements, CSV
  (abbreviation, text, name) and Shorthand's own export. Their dates, clipboard, cursor,
  fill-ins and nested snippets become Shorthand's; espanso's Markdown, HTML and images come
  in formatted. A preview lists every snippet with a checkbox and says what couldn't come
  along (key presses, scripts, shell commands, regex triggers). macOS's own list is never
  changed.
- **Export** Shorthand's own JSON (formatting included); a backup of the library every day
  (last 7).
- **Don't expand in**: password managers and Shorthand itself by default; add any app.
- **Pause** from the menu or a shortcut you set (Settings › Shortcuts). Paused means the
  keyboard listener is removed, not just ignored.

## Permissions

- **Accessibility** (to type and paste for you). macOS may also ask for **Input
  Monitoring** (to notice the keys you type); Shorthand asks for the second only if macOS
  still wants it after the first. The library shows a one-line row with a button to the
  right System Settings pane, and updates by itself when you allow it.
- **Paste from Other Apps** (macOS 15.4+): needed to put your clipboard back after a pasted
  snippet, and for `{clipboard}`. Until it's allowed, pasted snippets stay on the clipboard
  and `{clipboard}` stays empty; Shorthand never makes macOS interrupt your typing with an
  alert. The editor and the menu say so, with a button to the pane.

## Privacy

Shorthand sees the keys you type so it can spot abbreviations. It keeps **only the last 32
characters, in memory**, overwritten as you type and cleared whenever you click, switch
apps, press an arrow key or a shortcut. Nothing you type is ever written to disk, logged or
sent anywhere. While an excluded app is in front, while paused, while an input method
(Japanese, Chinese, Korean...) is on, and in password fields (macOS hides them from every
app), keys aren't even looked at. Shorthand stores your snippets and, per snippet, how many
times it was used and when. No network, no analytics, no account.

## Keyboard

| Where | Key | Action |
|---|---|---|
| Library | ⌘N / ⇧⌘N | New snippet / new group |
| Library | ⌘D | Duplicate |
| Library | ⌘⌫ | Delete (⌘Z undoes) |
| Library | ⌘F | Search |
| Library | Snippet › Insert Placeholder | Date, time, clipboard, cursor, fill-ins, another snippet |
| Library | ⇧⌘I | Import snippets |
| Library | ⌘B / ⌘I / ⌘U, ⌘T | Bold, italic, underline, fonts (formatted snippets) |
| Fill-in form | Tab, ↑↓, Space, Return, Esc | Move, change a choice, tick a section, insert, cancel |
| Search panel | ↑↓, Return, ⌘1–9, ⌘C, Esc | Choose, insert, insert row 1–9, copy, clear or close |
| Anywhere | (unset) | Insert a snippet (Settings › Shortcuts) |
| Anywhere | (unset) | Pause or resume expansion (Settings › Shortcuts) |

## Not there yet

Multi-line fill-in fields (imported ones become one line), key presses in snippets (Tab,
Return), the selected text as a placeholder, "expand after a space" timing, exporting to
other expanders' formats, importing TextExpander's newer backup formats
(`.textexpandersettings` and friends; save a group as a `.textexpander` file instead), and
sync. TextExpander's rich text comes in formatted only when the file carries it.

## Develop

```sh
scripts/test.sh Shorthand     # unit tests
scripts/run.sh Shorthand      # build a debug .app and open it
scripts/check.sh Shorthand    # the full gate: tests, release bundle, launch smoke test
```

- `Sources/ShorthandCore`: the rolling buffer, the reversed-trie matcher, the tap engine
  (word rule, case, keys typed meanwhile, undo), placeholders, insertion planning, the
  expander (behind `KeyPosting`, `InsertionEnvironment` and `TapControl` protocols), the
  library model, JSON store with backups, search; fill-ins (`FillIn.swift`), formatted text
  (`RichText.swift`: RTFD storage, assembly, RTF/HTML pasteboard data), imports
  (`TextReplacements.swift`, `TextExpanderImport.swift`, `EspansoImport.swift` with a small
  YAML subset parser in `MiniYAML.swift`, CSV), caret placement. Tested with fakes.
- `Sources/Shorthand`: the listen-only keyboard tap on its own thread (`KeyTap.swift`), the
  system services, the menu, the library window and editor, the fill-in form and search
  panels (`FillInPanel.swift`, `SearchPanel.swift`), the caret locator, the rich clipboard
  paster, Settings, test hooks.
- Typing and pasting use SlopKit's `SyntheticKeyboard`, `ClipboardPaster` and
  `ClipboardSnapshot` (shared with Dictate and Clips).

### Test mode

Environment variables (all listed in `Sources/Shorthand/Diagnostics.swift`) keep tests away
from your snippets, keyboard, clipboard and apps: `SHORTHAND_DATA_DIR`, `SHORTHAND_NO_TAP`,
`SHORTHAND_REPLAY` (feeds our own keystroke timeline into the real engine, in process),
`SHORTHAND_INSERT_ONLY_INTO=<bundle id>` (every key goes to that process only),
`SHORTHAND_PASTEBOARD`, `SHORTHAND_PASTE_PRIVACY`, `SHORTHAND_FAKE_REPLACEMENTS`,
`SHORTHAND_FAKE_APPS`, `SHORTHAND_ASSUME_TRUSTED`, `SHORTHAND_ASSUME_SECURE_INPUT`,
`SHORTHAND_TEST_HOOKS`, `SHORTHAND_SNAPSHOT_DIR`, `SHORTHAND_LOG`
(timings and decisions only, never typed text). Any test mode (and the smoke test) uses
its own settings and shortcut names, so it never picks up your shortcuts.

Design follows [`docs/design-system.md`](../../docs/design-system.md).
