# Brag Plan: NotchVoice

## What is this app?
A MacBook app that turns the notch into a hands-free voice assistant: say "Hey Notch" and it types into ChatGPT, opens apps, clicks the first link, reads your PDFs — 100% on-device on an 8 GB M2 (Laya-MLX decides, Whisper hears, OmniVoice talks).

## The angle
The notch is the most useless pixel real estate Apple ever shipped — a black bite out of your screen. NotchVoice makes it the most useful thing on the Mac. Quiet, confident, Apple-keynote restraint: the joke is only in the hook; the rest is pure demo.

## Hook (first 2-3 seconds)
Close-up of the top edge of a MacBook screen, the black notch center frame. Text types beside it: **"Your notch has done nothing since 2021."** Hold. The notch gives one tiny pulse, like it heard that.

## Key moments (the middle)
- The notch **drops down** into the real NotchVoice panel after a spoken "Hey Notch": green listening dot, "Notch" title, transcript line, it answers "Yes?".
- A chat box in a browser **types itself** from voice ("write best budget laptops for 2026") and a **"send"** clicks the send button — no hands.
- Voice commands **land one by one**: "open Notes" → "full screen" → "visit the first link" → "quit Safari", each with its action happening.
- A PDF is **dragged onto the notch**, file chip appears, "is it urgent?" → "Yes, it looks urgent." with Laya's **97%** confidence.

## Outro / punchline
"No cloud. No buttons. Just the notch." → NotchVoice wordmark in the notch shape, with the real on-device latencies: **Laya 25 ms · Whisper 110 ms**.

## User flow worth showing
Say "Hey Notch" → panel drops, "Yes?" → speak a command ("write …", "send", "open Notes", "visit the first link") → it happens in the other app while you keep your hands off the keyboard.

## Tone
- Preset: polished
- Creative direction: quiet Apple-keynote flex — "the notch finally does something"
- Interpretation: black stage, few words, long confident holds, soft crossfades/slides; one dry joke in the hook, then let the demo speak.

## Format: landscape — 1920x1080
## Duration: 21 seconds

## Visual identity (from the project)
- Background: `#000000` (the notch itself) with a subtle dark desktop `#0B0B0D`
- Accent: listening green `#34C759`, speaking blue `#0A84FF`, thinking orange `#FF9F0A` (the status dot in `AssistantView.swift`)
- Text: `#FFFFFF`, secondary `rgba(255,255,255,0.55)`
- Display font: SF Pro Rounded (`.system(.headline, design: .rounded)` in the app) — fall back to system-ui rounded
- Body font: SF Pro Rounded / system-ui
- Strongest visual element: the black notch morphing from its closed pill into the 600×160 rounded panel (NotchDrop's notch shape with inverted top corners), with the colored status dot and file chip capsule

## Share copy (draft)
My MacBook notch now listens: "Hey Notch" → it types into ChatGPT, opens apps, clicks links and reads PDFs — fully on-device on an 8 GB M2.

## Audio direction
- Role: warm bed with sparse, precise UI accents
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (114.8 BPM)
- Music treatment: start at 0, low under the hook, full by the notch drop, fade out over the last ~1.5 s
- Music cue guidance: preset read (`vol-11.music-cues.md`). Strong cues: **3.70 s** (notch drop), **8.96 s** (send click), **17.91 s** (outro wordmark). Beat grid for the command sequence: 10.54, 11.60, 12.65, 13.70 (one command per ~1.05 s, every other beat).
- Audio-reactive treatment: subtle — the green listening dot / panel glow may breathe with the bed; no waveform bars
- SFX posture: sparse, motion-matched, professional
- Audio-coupled moments: hook text typing (soft key ticks), notch drop (soft whoosh/pop), chat box typing (key ticks), send click, command chips landing (light UI ticks), file drop (soft thud), outro logo (one clean hit)
- Restraint rule: no cartoon sounds, no stacked hits, nothing louder than the music bed except the outro hit

## Storyboard

### Scene 1 — The useless notch — 3.0s
Top edge of a dark MacBook screen, notch centered. Hook line types out to its right: "Your notch has done nothing since 2021." Hold ~1.2 s. Notch does one tiny pulse at the end.
Sequential/interaction: yes — hook types character by character
Audio intent: quiet, a little dry
Audio-coupled idea: soft key ticks on the typing; music bed low
Music: low bed
Transition mood: clean → Scene 2

### Scene 2 — "Hey Notch" — 3.0s
A speech caption appears under the notch: “Hey Notch”. On the 3.70 s cue the notch **drops open** into the NotchVoice panel: green dot, "Notch", transcript “Hey Notch”, then the reply "Yes?" (blue dot while speaking). Small label: NotchVoice.
Sequential/interaction: yes — simulated voice input → notch expansion → reply
Audio intent: the "it's alive" moment
Audio-coupled idea: soft whoosh/pop on the drop, aligned to 3.70 s
Transition mood: soft slide → Scene 3

### Scene 3 — Types into ChatGPT — 4.5s
Panel shrinks back to the notch; below, a browser window with a centered chat composer ("Ask anything"). Speech caption: “write best budget laptops for 2026” — text types into the composer by itself. Caption: “send” → send button presses on the 8.96 s cue, message bubble moves up.
Sequential/interaction: yes — voice → text typing into a field → button click
Audio intent: satisfying, precise
Audio-coupled idea: key ticks while typing; one click on send at 8.96 s
Transition mood: clean → Scene 4

### Scene 4 — Controls everything — 4.5s
Four voice commands land one by one on the beat grid (10.54, 11.60, 12.65, 13.70), each as a notch transcript chip with its effect shown in a small tile: “open Notes” (Notes icon pops), “full screen” (window expands), “visit the first link” (first search result highlights and opens), “quit Safari” (window fades). Label: "Any app. Any button."
Sequential/interaction: yes — 4 commands arrive one by one
Audio intent: momentum
Audio-coupled idea: light UI tick per command landing
Transition mood: slide → Scene 5

### Scene 5 — Reads your files — 3.5s
A PDF icon "invoice.pdf" is dragged up into the notch; the notch opens, file chip capsule appears. Caption: “is it urgent?” → orange thinking dot → reply "Yes, it looks urgent." with a small badge "Laya · 97% · 25 ms".
Sequential/interaction: yes — drag & drop → question → answer
Audio intent: calm confidence
Audio-coupled idea: soft thud on the drop, tick on the answer
Transition mood: soft crossfade → Scene 6

### Scene 6 — Outro — 2.5s
Black. The notch shape holds the wordmark **NotchVoice**. Line: "No cloud. No buttons. Just the notch." Under it, small stat chips: "Laya-MLX 25 ms · Whisper 110 ms · 8 GB M2 · 100% on-device". Wordmark lands on 17.91 s; music fades.
Sequential/interaction: stat chips arrive one by one
Audio intent: clean, confident landing
Audio-coupled idea: one clean logo hit on 17.91 s
Transition mood: end

Scene durations: 3.0 + 3.0 + 4.5 + 4.5 + 3.5 + 2.5 = **21.0 s**

**Music mood for this video:** upbeat, warm, understated
**Audio summary:** a warm bed that starts low under the dry hook, lifts as the notch comes alive, carries a tight beat-synced command sequence, and lands on one clean logo hit before fading.
