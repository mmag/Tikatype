# Tikatype

macOS menu bar app that converts text between keyboard layouts — useful when you start typing in the wrong language.

## Features

- **Ctrl+Shift** — convert the last typed word
- **⌥ ⌥ (double Option)** — convert the phrase since the last sentence break
- **⌥⌃** — convert selected text
- Automatically switches the active layout after conversion
- Supports any two layouts (not just Russian ↔ English)
- Per-app exclusion list

## Installation

```bash
brew tap mmag/tap
brew install --cask tikatype
```

Launch Tikatype from Applications. On first run, grant Accessibility permission when prompted — it's required for keyboard monitoring.

## Usage

Type text in the wrong layout, then:

| Hotkey | Action |
|--------|--------|
| Ctrl+Shift | Convert last word |
| ⌥ ⌥ | Convert phrase (since last `.`, `!`, or `?`) |
| ⌥⌃ | Convert selection |

Open the menu bar icon to configure layouts, excluded apps, and launch-at-login.

## Requirements

- macOS 13 or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Build from source

```bash
git clone https://github.com/mmag/Tikatype.git
cd Tikatype
swift build -c release
```
