# NotchVoice

Talk to your Mac through the notch. Say **"Hey Notch"** and it opens apps, types into any text box, presses keys and buttons, clicks links in Chrome, and reads your files — hands-free and **100% on-device**. Built and tested on an 8 GB M2 MacBook Air.

| Piece | What it does |
|---|---|
| **Notch UI** | SwiftUI panel that drops out of the notch (forked from [NotchDrop](https://github.com/Lakr233/NotchDrop), MIT) |
| **Whisper** (`whisper.cpp` server) | Hears you — speech → text, ~110 ms |
| **[Laya-MLX](https://github.com/mizorewww/laya-mlx)** | Decides what you meant — typed choices with calibrated confidence, ~25 ms. No text generation. |
| **OmniVoice** (GGUF build from [VoiceStudio](https://github.com/debpalash/VoiceStudio)) | Talks back |

## What you can say

Start with **"Hey Notch"** — then keep talking until you say **"bye"** (or 30 s of silence).

| Say | Does |
|---|---|
| "open Notes" · "open Antigravity and Notes" | Opens apps (fuzzy match, tolerates mishearing) |
| "write how are you" … keep talking … "stop typing" | Dictates into the focused text box — auto-focuses ChatGPT/Claude/search boxes |
| "send" · "press enter" · "press command shift T" | Any key or combo; "send" clicks the Send button |
| "click Submit" · "click the search field" · "click the second button" | Any button / menu item / link / field by name, via Accessibility |
| "full screen" · "close tab" · "quit Safari" · "volume up" · "lock screen" | ~40 window / app / system controls |
| "search for …" · "visit the first link" · "go to github.com" | Chrome, Brave, Edge, Arc, Vivaldi, Safari |
| "key points of this page" · "read this file" · "is it urgent?" | Reads dropped files or the current web page |
| "turn on focus mode" | Runs one of your Apple Shortcuts (Laya picks the closest) |

## Setup

Requirements: Apple Silicon Mac, macOS 14+, Homebrew, [uv](https://github.com/astral-sh/uv), cmake, Xcode Command Line Tools (full Xcode not needed).

```bash
git clone https://github.com/Starlord-999/notchvoice ~/Documents/notch
~/Documents/notch/scripts/setup.sh      # models (~2 GB), Laya venv, OmniVoice build, signing identity, app
open ~/Documents/notch/NotchVoice/build/NotchVoice.app
```

Grant when asked: **Microphone**, **Accessibility** (typing, keys, clicks), and **Automation** for your browser. For "visit the first link" in Chrome, enable **View → Developer → Allow JavaScript from Apple Events**.

The app expects the project at `~/Documents/notch`; to use another folder: `defaults write dev.puneet.NotchVoice root /path/to/notch`.

## Layout

```
NotchVoice/          Swift app (SwiftPM, no Xcode project) — Sources/NotchVoice/*.swift, build.sh
sidecar/             laya_server.py — Laya decisions + OmniVoice speech on 127.0.0.1:8179
scripts/setup.sh     one-shot setup
PLAN.md              design notes, findings and measurements
```

Logs: `~/Library/Logs/NotchVoice.log`. Self-checks: `swift build && .build/debug/NotchVoice --check` and `sidecar/.venv/bin/python sidecar/laya_server.py --check`.

## Known limits

- Laya can't write text: no free-form answers or summaries ("key points" quotes the most important sentences).
- OmniVoice takes ~3 s per new sentence on an M2; fixed replies are cached and instant.
- With a session open it trusts what it hears — background TV can trigger actions. "Always require Hey Notch" in the menu-bar icon makes it strict.

## License

[AGPL-3.0](LICENSE) © 2026 Puneet Dugar. You can use, modify and redistribute NotchVoice, but any distributed or network-served modified version must also be released under AGPL-3.0 with its source.

Third-party: NotchDrop (MIT, notice kept in `NotchVoice/LICENSE-NotchDrop`), Laya-MLX (Apache-2.0), VoiceStudio/OmniVoice (AGPL-3.0, built separately by `setup.sh`, not vendored), whisper.cpp (MIT). Model weights carry their own licenses.
