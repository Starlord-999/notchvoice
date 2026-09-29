"""25 s Twitter cut of the raw recording: speed-ramped, X feed blurred, event times printed."""
import subprocess, os, json
SRC = os.path.expanduser("~/Desktop/notch voice.mp4")
BLUR = "crop=2340:1210:300:250,boxblur=28:4"   # Chrome page area (source px), keeps tab + address bar
# (src_start, src_end, speed, keep_audio, blur)
SEG = [
    (0.55, 1.15, 1.0, True, False),   # "Hey Notch"
    (1.15, 2.25, 2.5, False, False),  # app responding (sped up so the panel pops fast)
    (2.25, 5.10, 1.0, True, False),   # panel "Hey Notch." -> "Open Chrome"
    (5.10, 7.95, 4.0, False, True),   # Chrome opens on X feed
    (7.95, 11.60, 1.0, True, True),   # "Search for latest laptop in 2026" (X feed still showing)
    (11.60, 13.70, 3.0, False, True), # navigating
    (13.70, 15.70, 1.0, False, False),# laptop results, held
    (33.85, 36.60, 1.2, True, True),  # "Search for MacBook M4 review" (misheard page blurred)
    (36.60, 42.00, 5.0, False, True), # loading
    (42.00, 44.40, 5.0, False, False),# MacBook M4 results
    (44.40, 46.40, 1.0, True, False), # "Click the first link"
    (46.40, 49.60, 2.5, False, False),# review article opens
    (52.00, 55.00, 1.0, True, False), # "Make Chrome full screen"
    (55.00, 56.30, 1.3, False, False),# full screen
]
EVENTS = {"hey": 0.72, "panel_open": 1.4, "debug_on": 2.25, "debug_off": 4.3, "open_chrome": 2.4, "chrome_open": 5.6,
          "search1": 8.1, "search1_end": 11.5, "results1": 13.7, "search2": 34.0, "search2_end": 36.5,
          "results2": 42.0, "first_link": 44.7, "first_link_end": 45.5, "article": 48.0,
          "fs_say": 52.1, "fs_say_end": 53.6, "fullscreen": 54.6}

def out_time(t):
    o = 0.0
    for s, e, sp, *_ in SEG:
        if s <= t <= e: return round(o + (t - s) / sp, 2)
        o += (e - s) / sp
    return None

parts, labels = [], []
for i, (s, e, sp, keep, blur) in enumerate(SEG):
    v = f"[0:v]trim={s}:{e},setpts=(PTS-STARTPTS)/{sp},fps=30"
    if blur:
        parts.append(f"{v},split[b{i}][o{i}]")
        parts.append(f"[b{i}]{BLUR}[bb{i}]")
        parts.append(f"[o{i}][bb{i}]overlay=300:250,scale=1920:-2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[v{i}]")
    else:
        parts.append(f"{v},scale=1920:-2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1[v{i}]")
    vol = "volume=22dB,alimiter=limit=0.9" if keep else "volume=0"
    tempo = f",atempo={sp}" if sp != 1.0 else ""
    parts.append(f"[0:a]atrim={s}:{e},asetpts=PTS-STARTPTS{tempo},{vol}[a{i}]")
    labels.append(f"[v{i}][a{i}]")
parts.append("".join(labels) + f"concat=n={len(SEG)}:v=1:a=1[v][a]")
out = "composition/assets/footage.mp4"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", SRC, "-filter_complex", ";".join(parts),
                "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "16", "-preset", "medium",
                "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out], check=True)
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", out, "-vn", "-c:a", "aac", "-b:a", "192k",
                "composition/assets/footage-audio.m4a"], check=True)
total = round(sum((e - s) / sp for s, e, sp, *_ in SEG), 2)
res = {"duration": total, "events": {k: out_time(v) for k, v in EVENTS.items()}}
json.dump(res, open("edit-times.json", "w"), indent=1)
print(json.dumps(res, indent=1))
