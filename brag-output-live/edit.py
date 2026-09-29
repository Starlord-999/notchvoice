"""Cut the raw screen recording into the edited footage + print output times of key moments."""
import subprocess, os, json
SRC = os.path.expanduser("~/Desktop/notch voice.mp4")
# (src_start, src_end, speed, keep_audio)
SEG = [
    (0.40, 5.60, 1.0, True),   # "Hey Notch" -> panel -> "Open Chrome"
    (5.60, 8.00, 2.0, False),  # Chrome opening
    (8.00, 12.40, 1.0, True),  # "Search for latest laptop in 2026"
    (12.40, 17.20, 2.4, False),# results load
    (33.80, 37.40, 1.0, True), # "Search for MacBook M4 review"  (misheard retry 17-33 cut)
    (37.40, 44.40, 3.5, False),# results load
    (44.40, 46.60, 1.0, True), # "Click the first link"
    (46.60, 51.80, 2.2, False),# article opens
    (51.80, 55.20, 1.0, True), # "Make Chrome full screen"
    (55.20, 62.00, 2.3, False),# full screen hold
]
EVENTS = {"hey": 0.72, "open_chrome": 2.4, "chrome_open": 6.6, "search1": 8.1, "results1": 15.8,
          "search2": 34.0, "results2": 42.0, "first_link": 44.7, "article": 48.5,
          "fullscreen_say": 52.1, "fullscreen": 54.6, "panel_open": 1.8, "panel_close": 4.9}

def out_time(t):
    o = 0.0
    for s, e, sp, _ in SEG:
        if s <= t <= e: return round(o + (t - s) / sp, 2)
        o += (e - s) / sp
    return None

parts, labels = [], []
for i, (s, e, sp, keep) in enumerate(SEG):
    parts.append(f"[0:v]trim={s}:{e},setpts=(PTS-STARTPTS)/{sp},fps=30,scale=1920:-2,pad=1920:1080:(ow-iw)/2:(oh-ih)/2[v{i}]")
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
total = sum((e - s) / sp for s, e, sp, _ in SEG)
times = {k: out_time(v) for k, v in EVENTS.items()}
json.dump({"duration": round(total, 2), "events": times}, open("edit-times.json", "w"), indent=1)
print(json.dumps({"duration": round(total, 2), "events": times}, indent=1))
