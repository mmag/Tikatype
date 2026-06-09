# Changelog

## 1.0.3 — 2026-06-09

### Fixed

- **Keys that are letters in another layout** (e.g. `.` = `ю` in Russian): pressing such a key while in a different layout no longer clears the phrase buffer. The keystroke is now buffered normally and converted correctly, so words like `вьюга` typed as `bm.uf` in English now convert in full.
- **Browser text fields**: converting the last word no longer deletes the entire field content. The AX-based replacement now reads the current field value and replaces only the trailing characters that belong to the converted word, preserving all preceding text.

## 1.0.1 — 2026-05-10

### Fixed

- **Spotlight and single-line fields**: conversion no longer leaves the first character behind. Root cause was that `NSWorkspace.shared.frontmostApplication` returns the last regular app, not Spotlight (a system overlay). Fixed by using `AXUIElementCreateSystemWide()` to get the truly focused element, then writing the converted text directly via `kAXValueAttribute` instead of backspace + paste.
- **Permissions prompt**: the app now also checks for **Input Monitoring** permission at launch and shows a dedicated alert pointing to the correct System Settings panel. Previously only Accessibility was checked, leaving the keyboard monitor silently non-functional when Input Monitoring was missing.

### Added

- **Re-conversion**: pressing the hotkey again after a conversion cycles the text back to the original layout. Works for Ctrl+Shift (word) and ⌥⌥ (phrase). Any new keystroke resets the cycle.

## 1.0.0 — 2026-05-08

Initial release.
