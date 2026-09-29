# Hyperframes Composition Brief: NotchVoice

## Objective
Create a short launch-style brag video for NotchVoice — a hands-free, on-device voice assistant that lives in the MacBook notch.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 21 seconds

## Source Material
- Project root: `/Users/puneet/Documents/notch`
- Primary files read: `PLAN.md`, `NotchVoice/Sources/NotchVoice/{NotchView,AssistantView,Assistant,Actions,Browser}.swift`, `sidecar/laya_server.py`, app log of real sessions
- Product name: NotchVoice
- Tagline / strongest claim: "Hey Notch" — it types into ChatGPT, opens apps, clicks links and reads PDFs, 100% on-device on an 8 GB M2
- Key UI to recreate: the black notch morphing into the 600×160 rounded panel (NotchDrop shape: flat top flush with the screen edge, rounded bottom corners, inverted small curves where it meets the top edge). Inside: status dot (8px circle) + "Notch" title (rounded headline), right-aligned file chip capsule (doc icon + filename, white 12% fill), transcript line in quotes (rounded title3), status line in secondary gray at the bottom.
- Copy that must appear verbatim:
  - "Your notch has done nothing since 2021."
  - "Hey Notch"
  - "Yes?"
  - "write best budget laptops for 2026"
  - "send"
  - "open Notes" · "full screen" · "visit the first link" · "quit Safari"
  - "is it urgent?" → "Yes, it looks urgent."
  - "No cloud. No buttons. Just the notch."
  - "Laya-MLX 25 ms · Whisper 110 ms · 8 GB M2 · 100% on-device"

## Creative Direction
- Tone preset: polished
- Creative direction: quiet Apple-keynote flex — "the notch finally does something"
- Interpretation: black stage, few words, confident holds, soft crossfades/slides. One dry joke in the hook, then pure demo.
- Angle: the notch is dead screen space; NotchVoice makes it the most useful thing on the Mac, without touching the keyboard.
- Hook: top edge of a MacBook screen with the notch; "Your notch has done nothing since 2021." types beside it, holds, notch pulses once.
- Outro / punchline: "No cloud. No buttons. Just the notch." + NotchVoice wordmark + real latency chips.
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals, waveform/equalizer graphics
  - Real ChatGPT/Apple logos — use a neutral chat composer ("Ask anything") and simple app tiles

## Visual Identity
- Background: `#000000` notch, desktop `#0B0B0D` with a very soft top vignette
- Text: `#FFFFFF`, secondary `rgba(255,255,255,0.55)`
- Accent: status dot — listening `#34C759`, speaking `#0A84FF`, thinking `#FF9F0A`, idle gray
- Display font: SF Pro Rounded → CSS `ui-rounded, "SF Pro Rounded", system-ui, sans-serif`
- Body font: same family
- Visual references: notch shape + panel, status dot colors, file chip capsule, speech captions as simple white rounded text with a small mic glyph

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

1. The useless notch — 3.0s — MacBook top edge, notch; hook line types; notch pulses.
2. "Hey Notch" — 3.0s — speech caption; notch drops open into the panel on 3.70 s; "Yes?" with blue dot.
3. Types into ChatGPT — 4.5s — browser chat composer types itself from voice; "send" clicks on 8.96 s.
4. Controls everything — 4.5s — 4 commands land one by one (10.54, 11.60, 12.65, 13.70) each with its effect tile; label "Any app. Any button."
5. Reads your files — 3.5s — invoice.pdf dragged into the notch, chip appears, "is it urgent?" → "Yes, it looks urgent." + "Laya · 97% · 25 ms".
6. Outro — 2.5s — wordmark on 17.91 s, line, stat chips, fade.

## Audio
- Audio role: warm bed with sparse UI accents
- Audio arc: low under the hook, lifts on the notch drop, carries the command run, lands one clean hit on the wordmark, fades out
- Music: `assets/music/happy-beats-business-moves-vol-11-by-ende-dot-app.mp3`
- Music treatment: start at 0, ~0.35 volume under hook rising to ~0.6, fade over final ~1.5 s
- Music cue guidance: preset `~/.claude/plugins/cache/brag/brag/0.2.2/skills/brag/assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.json`; strong locks 3.70 s, 8.96 s, 17.91 s; beat grid for commands 10.54 / 11.60 / 12.65 / 13.70
- Audio-reactive treatment: subtle — listening-dot glow / panel shadow breathes with RMS; no visualizers
- Audio-coupled moments:
  - Scene 1 hook typing — keypress ticks
  - Scene 2 notch drop — soft drop/whoosh
  - Scene 3 composer typing — keypress ticks; send — click
  - Scene 4 command landings — light UI tick each
  - Scene 5 file drop — soft thud; answer — tick
  - Scene 6 wordmark — one clean hit
- SFX selection guidance: restrained, low high-frequency risk; per `sfx-analysis.md`
- SFX analysis guidance: `~/.claude/plugins/cache/brag/brag/0.2.2/skills/brag/assets/sfx/sfx-analysis.md`
- Exact SFX choice: chosen during composition to match implemented motion
- Audio files: copied into `brag-output/composition/assets/`

## Hyperframes Instructions
Use hyperframes-core / animation / creative / keyframes / cli. Show the real NotchVoice panel UI, keep all text readable, 21 s total, include music + SFX, 1–3 strong-cue locks, `hyperframes check` must pass before render.

## Implementation notes (post-build)
- Audio-reactive treatment: intentionally skipped — polished tone + a dark, text-led stage; the beat-locked notch drop (3.70 s), send click (8.96 s) and wordmark (17.91 s) carry the musicality instead.
- `check`: 0 errors, 0 contrast failures; 7 structural advisories (monolithic file) accepted because the persistent notch spans every scene on one timeline.
