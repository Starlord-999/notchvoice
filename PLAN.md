# Notch Voice — Plan

A macOS app that lives in the MacBook notch. Drop a file on it or talk to it — hands-free, no buttons.
Everything runs on-device.

**Target machine:** Apple M2, **8 GB RAM**, macOS 26.6.

---

## 1. Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Brain | **Laya-MLX only** — no text-generating LLM | It picks from fixed options with a calibrated confidence in ~10–30 ms. It cannot write text. |
| Notch UI | **Fork [NotchDrop](https://github.com/Lakr233/NotchDrop)** (MIT, 27 Swift files) | Notch window + file drop tray, nothing else. boring.notch was checked: 123 files of music/HUD/calendar to strip, GPL-3. |
| Ears (speech → text) | **Whisper** via **whisper.cpp `whisper-server`** (already installed via Homebrew, Metal GPU) | No new install. `whisper-vad-speech-segments` / built-in VAD also present. |
| Mouth (text → speech) | **VoiceStudio** backend, engine **OmniVoice GGUF (Q8_0, ~945 MB)**, speaking in the user's **cloned voice** | User already clones voices with OmniVoice. Full-precision OmniVoice needs ~6 GB; the quantized build (`OMNIVOICE_TTS_BACKEND=omnivoice-gguf`) fits 8 GB. |
| Interaction | Always listening, no buttons, confidence-gated | See §4. |
| Privacy | 100 % local. No network after first-run model downloads. | User requirement. |

**Out:** Qwen / any LLM, full-precision OmniVoice, Parakeet, cloud APIs, boring.notch, Jev (cloud-only).

---

## 2. What it can and cannot do

Laya answers only three question types: **choice** (pick one), **score** (rubric level), **noul** (yes/no probability).
Input is text only, max 1,024 tokens (multilingual checkpoint) per call.

| Can | Cannot |
|---|---|
| Open / close / stop / dismiss by voice | Summarize in its own words |
| "Read this file" (reads extracted text aloud) | Answer free-form questions |
| "Key points" — Laya scores each paragraph, top 3 are read aloud verbatim | Explain its choice |
| "Is this urgent?" / "What kind of file is this?" (invoice, contract, receipt…) | Reliable dates / counting (known weakness) |
| "Find the part about X" — Laya picks the best-matching paragraph | Understand images/audio directly (OCR / Whisper first) |

---

## 3. Architecture

```
┌─────────────── NotchVoice.app (Swift, NotchDrop fork) ───────────────┐
│  Mic: AVAudioEngine, voice processing ON (echo cancel)               │
│  VAD: energy gate → only speech segments leave the app               │
│  Notch UI: listening dot · transcript · file chip · status           │
│  File ingest: PDFKit (PDF) · Vision OCR (images) · plain text        │
│  Process manager: starts/stops the 3 local servers below             │
└──────┬──────────────────────┬─────────────────────────┬──────────────┘
       │ WAV segment           │ text + questions        │ text
       ▼                       ▼                         ▼
 whisper-server          laya sidecar (Python)      VoiceStudio backend
 127.0.0.1:8178          127.0.0.1:8179             127.0.0.1:3900
 ggml-base.en / small    laya-multilingual-mlx      OmniVoice GGUF Q8_0 + cloned voice
 → transcript            → answers + confidences    → WAV → speaker
```

All servers bind to `127.0.0.1` only.

### Laya sidecar
One Python file, stdlib `http.server`, one endpoint:

```
POST /decide   {"state": "...", "questions": {...}}  →  laya agent.predict(...) result
```

Model loaded once at start (`laya.load("aac6fef/laya-multilingual-mlx")`, FP16, ~0.7 GB).
Swift owns all question definitions; the sidecar is a dumb pipe.

---

## 4. Hands-free loop

```
speech segment → Whisper → text
  → Laya (one call, 3 questions):
       addressed : noul   "Is the speaker talking to the assistant?"
       intent    : choice open · close · stop · read_file · key_points ·
                          find_in_file · what_is_file · is_urgent · ignore
       (+ state includes: panel open? file loaded? assistant speaking?)
  → gate on confidence
  → act → VoiceStudio speaks the result
```

### Confidence gate (tune in Phase 0)

| max(addressed × intent) | Action |
|---|---|
| ≥ 0.90 | Act immediately |
| 0.60 – 0.90 | Confirm aloud ("Read the PDF?") → next utterance → Laya noul "Is this a yes?" |
| < 0.60 | Ignore silently |

### Wake behaviour
- Panel **closed**: stricter — also require the utterance to start with "Notch …" / "Hey Notch" (string check after Whisper). Cuts false triggers from calls/video.
- Panel **open**: conversational, no wake phrase, Laya `addressed` does the filtering.
- Panel auto-closes after 20 s of no addressed speech.

### Barge-in
While TTS plays, VAD still runs. Any speech segment → stop playback immediately → process the new utterance.
Echo cancel (`AVAudioInputNode.setVoiceProcessingEnabled(true)`) keeps the app from hearing itself.

---

## 5. File flows

| Trigger | Behaviour |
|---|---|
| Drag file over notch | Notch expands (NotchDrop already does this), drop → file chip shown, says "Got *name*." |
| "Notch, look at this" | Takes current Finder selection (AppleScript `tell application "Finder" to get selection`) |

After ingest the text is split into paragraphs (≤ ~200 tokens each) and kept in memory for the session.

| Intent | Implementation |
|---|---|
| `read_file` | Stream paragraphs to TTS in order; "stop" interrupts |
| `key_points` | Laya `score` "How important is this paragraph to the document's main point?" on each paragraph (batched) → read top 3 |
| `find_in_file` | Laya `noul` "Does this paragraph answer: *<user's words>*?" on each paragraph → read the best one if ≥ 0.6, else "Couldn't find that." |
| `what_is_file` | Laya `choice` over {invoice, receipt, contract, resume, letter, report, notes, code, other} on the first 1,000 tokens |
| `is_urgent` | Laya `noul` "Does this communicate a deadline or time pressure?" on the first 1,000 tokens |

Supported types v1: PDF, TXT/MD, images (PNG/JPG/HEIC via Vision OCR), DOCX via `NSAttributedString(url:)`.

---

## 6. RAM budget (8 GB)

| Component | Est. RAM |
|---|---|
| Laya multilingual 322M FP16 | ~0.7 GB |
| whisper.cpp `base.en` (fallback `small`) | ~0.2 GB (0.5 GB) |
| VoiceStudio backend + OmniVoice GGUF Q8_0 | ~1.5 GB |
| NotchVoice.app | ~0.1 GB |
| **Total** | **~2.5–2.8 GB** |

Leaves ~5 GB for macOS + browser. If memory pressure shows up: drop OmniVoice to Q4_K_M (~659 MB).

---

## 7. Build order — small wins, one continuous run

Each win is tiny, runs on its own, and has one test. Next win starts only when the current test passes.
No phases, no waiting — built straight through.

| # | Win | Test (pass = move on) |
|---|---|---|
| 1 | Laya answers | `python sidecar/laya_server.py` → `curl /decide` "open the notch" → `intent=open` ≥ 0.9, < 50 ms |
| 2 | Whisper hears | `whisper-server` + `curl` a recorded "Notch, read this file" WAV → correct text, < 500 ms |
| 3 | OmniVoice speaks in cloned voice | VoiceStudio backend headless, `omnivoice-gguf` → "Hello Puneet" WAV plays in cloned voice, < 700 ms first audio |
| 4 | Ear → brain → mouth (CLI) | Script: WAV → Whisper → Laya → OmniVoice → speaker. End-to-end < 1.5 s |
| 5 | Notch appears | NotchDrop fork builds, opens/closes the notch from code |
| 6 | Live mic + VAD | Talk → transcript shows in the notch; silence sends nothing |
| 7 | Hands-free commands | "Hey Notch, open" / "close" / "stop" work; TV/background speech ignored (gate thresholds tuned here) |
| 8 | It talks back + barge-in | Replies in cloned voice; talking over it stops playback; it doesn't hear itself |
| 9 | File drop | Drop PDF/image/txt → chip shows, text extracted, "Got *name*" spoken |
| 10 | File voice actions | read_file · key_points · find_in_file · what_is_file · is_urgent each work on 3 real files |
| 11 | Runs itself | App launches all 3 servers, restarts on crash, quits cleanly; RAM < 3 GB total |
| 12 | Ship | Settings (voice, wake phrase, thresholds), launch at login, `scripts/setup.sh`, signed DMG |

Wins 1–4 prove the whole stack without any UI. If one fails, fix or swap that single piece
(e.g. OmniVoice Q4_K_M, Whisper `small`) before touching anything else.

### Needs before starting
- Downloads (~2.5 GB total): `laya-mlx` + `aac6fef/laya-multilingual-mlx` (~0.7 GB), `ggml-base.en.bin` (~150 MB),
  VoiceStudio backend + OmniVoice GGUF Q8_0 (~1.5 GB incl. deps), NotchDrop source.
- Path to the reference audio of the user's cloned voice.

---

## 7b. Status & findings (2026-09-29)

Built: wins 1–11 in code; `scripts/setup.sh` + `NotchVoice/build.sh` for win 12 (DMG/notarization not done).

| Finding | Consequence |
|---|---|
| Laya: bare labels score 0.2–0.5; described options score 0.9+ | Every choice option has a one-line description |
| Laya is weak on one-word commands ("stop", "enough") | Stop words + yes/no are keyword rules (`Words.swift`), Laya only for the rest |
| Laya `addressed?` noul unreliable (0.36 on "read this file"); background TV hit 0.95 intent confidence | **"Hey Notch" always required.** Exceptions: "stop" while speaking, yes/no within 8 s of a question |
| Whisper spells it "Natch" | `prompt="Hey Notch."` + spelling variants; wake phrase found anywhere in a transcript |
| OmniVoice GGUF on M2: ~3 s per short sentence (Q8_0 and Q4_K_M same) — slower than real time | Fixed replies pre-rendered + cached (instant); file sentences prefetched on drop; read-aloud has gaps |
| OmniVoice binary only synthesizes after stdin EOF | One warm spare process per reply (model preloaded) |
| VoiceStudio's upstream build leaves a bad rpath | `setup.sh` patches with `install_name_tool` |
| AVAudioEngine voice processing fails (-10875) if enabled before the player is connected | Connect player first; set other-audio ducking to min |
| Energy VAD in a room with continuous background speech hits the max segment | Max segment 8 s; wake phrase searched mid-transcript. Upgrade: Silero/whisper VAD or rolling window |
| VoiceStudio's Python server not needed | Only its OmniVoice GGUF engine binary is used (same model, no 1.8 GB server) |

## 7c. Other apps (added)

| Say | How |
|---|---|
| "Hey Notch, open Safari" / "can you open notes" | Verb found anywhere + fuzzy match against installed app names (plain code; Laya can't choose from 100+ apps) |
| "Hey Notch, type Hello Sam, see you at 5." | Whisper text pasted into the frontmost app (clipboard restored). Needs **Accessibility** permission |
| "Hey Notch, turn on focus mode" | Laya picks from the user's **Apple Shortcuts** (`shortcuts list`) — any task built in Shortcuts becomes a voice command |
| "Hey Notch" … "Yes?" … next sentence | 8 s follow-up window: no second wake phrase needed |

| "Hey Notch, full screen / close tab / quit / minimize / new tab / undo / copy / paste / save / zoom in / scroll down / volume up / mute / lock screen …" | ~40 phrase → standard macOS shortcut on the app the user was in (`Actions.controls`). One-word phrases only fire as the whole command |
| "Hey Notch, quit Safari" / "hide Slack" | Matches running apps by name → terminate / hide |

| "Hey Notch" … (no wake phrase until "bye" / 30 s idle) | Session; menu-bar icon fills while listening |
| "write …" then keep talking … "stop typing" | Dictation across pauses; "send", "press enter", "new line", "scratch that" stay commands |
| "press enter" / "press command shift T" / "send" / "click Submit" / "click the search field" | Any key combo; any button, menu item, link or text field by name via Accessibility (Electron apps too) |
| "click the second button" / "first field" | n-th element of that kind in the front window, in reading order |
| Browser: "visit the first link" / "open the third result" / "click Sign in" / "search for X" / "go to github.com" / "key points of this page" | Chrome, Brave, Edge, Arc, Vivaldi, Safari via AppleScript + page JavaScript (needs *Allow JavaScript from Apple Events*) |

App is signed with a local self-signed identity ("NotchVoice Local Signing") so permissions survive rebuilds.
Voice-opening never steals keyboard focus from the app being typed in.

## 8. Risks

| Risk | Mitigation |
|---|---|
| False triggers from an always-on mic | Wake phrase when closed + Laya `addressed` + confidence gate |
| Laya misreads short/odd commands | Tune criteria wording in Phase 0; keep intent list small |
| VoiceStudio backend may expect its Electron shell | Verify in Phase 0; fallback: run the OmniVoice GGUF binary directly |
| Whisper mishears names/jargon | Use `small` model if `base.en` is too weak; RAM allows it |
| 8 GB memory pressure | OmniVoice Q4_K_M, Whisper `base.en`, lazy-load VoiceStudio on first reply |
| OmniVoice GGUF first-word delay on M2 | Measured in Phase 0; short replies (≤ 1 sentence) keep it low; stream paragraph-by-paragraph for read-aloud |
| Licences | NotchDrop MIT ✅. Laya Apache-2.0 ✅. VoiceStudio AGPL — used as a separate local server, not linked ✅. |

---

## 9. Not in v1
Free-form answers / summaries (needs an LLM — doesn't fit the Laya-only + 8 GB constraint) ·
chat memory across sessions · multi-step tasks beyond Apple Shortcuts · folder-wide search · Intel Macs · Downloads-folder auto-peek.

---

## 10. Repo layout (planned)

```
notch/
  PLAN.md
  NotchVoice/          # NotchDrop fork (Xcode project)
  sidecar/
    laya_server.py
  scripts/
    setup.sh           # venvs + model downloads
```
