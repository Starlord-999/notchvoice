"""Brain + mouth sidecar. Binds 127.0.0.1 only.

POST /decide {"state": ..., "questions": {...}} -> laya predict result (Swift owns the questions)
POST /speak  {"text": ...}                      -> {"wav": path}  OmniVoice, cached by text

Run: .venv/bin/python laya_server.py [port]      Self-check: .venv/bin/python laya_server.py --check
"""
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

import laya_mlx as laya

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "models"
CACHE = MODELS / "tts-cache"
OMNIVOICE = [str(ROOT / "vendor/VoiceStudio/bin/omnivoice-tts-darwin-arm64"),
             "--model", str(MODELS / "omnivoice-base-Q8_0.gguf"),
             "--codec", str(MODELS / "omnivoice-tokenizer-Q8_0.gguf"),
             "--lang", "en", "--seed", "42", "-o", "-"]
VOICE = []  # ["--ref-wav", path, "--ref-text", path] once the user's cloned voice is wired in

MODEL = "aac6fef/laya-multilingual-mlx"
agent = laya.load(MODEL)
laya_thread = ThreadPoolExecutor(1)  # MLX is fast on one long-lived thread, slow on fresh ones
tts_lock = Lock()


def _spawn():
    # Loads the model (~3 s) then blocks on stdin; OmniVoice only synthesizes after stdin EOF,
    # so each process serves one reply. ponytail: one warm spare, add a pool if replies overlap.
    p = subprocess.Popen(OMNIVOICE + VOICE, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL)
    return p


spare = None


def speak(text):
    global spare
    CACHE.mkdir(parents=True, exist_ok=True)
    wav = CACHE / (hashlib.sha1(text.encode()).hexdigest()[:16] + ".wav")
    if wav.exists():
        return str(wav), True
    with tts_lock:
        p, spare = (spare or _spawn()), _spawn()
        out, _ = p.communicate(text.encode())
    data = bytearray(out)
    data[4:8] = (len(data) - 8).to_bytes(4, "little")    # streamed WAV has unknown sizes;
    data[40:44] = (len(data) - 44).to_bytes(4, "little")  # patch RIFF + data chunk sizes
    tmp = wav.with_suffix(".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, wav)
    return str(wav), False


def _decide(state, questions):
    t = time.perf_counter()
    out = agent.predict(state, questions)
    out["ms"] = round((time.perf_counter() - t) * 1000, 1)
    return out


def decide(state, questions):
    return laya_thread.submit(_decide, state, questions).result()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # health check
        self._send(200, {"ok": True, "model": MODEL})

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            if self.path == "/decide":
                return self._send(200, decide(body["state"], body["questions"]))
            if self.path == "/speak":
                t = time.perf_counter()
                path, cached = speak(body["text"])
                return self._send(200, {"wav": path, "cached": cached,
                                        "ms": round((time.perf_counter() - t) * 1000)})
            self._send(404, {"error": "not found"})
        except Exception as e:
            self._send(400, {"error": str(e)})

    def _send(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


def check():
    q = {"intent": {"type": "choice", "instructions": "What does the user want?",
                    "criteria": ["open", "close", "stop", "ignore"]}}
    decide("warm up", q)
    for text, want in [("Hey notch, open up", "open"), ("close the notch", "close"),
                       ("stop talking", "stop")]:
        r = decide(text, q)
        got = r["answers"]["intent"]["choice"]
        print(f"{text!r:28} -> {got:6} {r['answers']['intent']['confidence']:.2f}  {r['ms']} ms")
        assert got == want, (text, got)
    path, _ = speak("Self check.")
    assert Path(path).stat().st_size > 10_000, "omnivoice produced no audio"
    assert speak("Self check.") == (path, True), "cache miss"
    print("ok")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        def _quit(*_):
            if spare:
                spare.kill()
            os._exit(0)
        signal.signal(signal.SIGTERM, _quit)
        signal.signal(signal.SIGINT, _quit)
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 8179
        print(f"laya on 127.0.0.1:{port}", flush=True)
        ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
