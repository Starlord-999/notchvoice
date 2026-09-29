"""Win 4: WAV -> Whisper -> Laya -> OmniVoice -> speaker. Needs whisper-server :8178 and laya_server :8179 running.

Usage: python3 e2e_check.py [phrase ...]   (phrases are spoken with `say` to make test WAVs)
"""
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

INTENTS = {"type": "choice", "instructions": "What does the user want the notch assistant to do?",
           "criteria": {"open": "open, show or expand the notch panel",
                        "close": "close, hide or dismiss the notch panel",
                        "stop": "user says stop, quiet, shut up, enough or pause",
                        "read_file": "read the dropped file aloud",
                        "ignore": "not a command for the assistant; background talk"}}
REPLIES = {"open": "Opening.", "close": "Closing.", "stop": "", "read_file": "Reading the file now.",
           "ignore": ""}


def post(url, body, ctype="application/json"):
    req = urllib.request.Request(url, body, {"Content-Type": ctype})
    return json.load(urllib.request.urlopen(req, timeout=60))


def transcribe(wav):
    b = uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\n"
            f"Content-Type: audio/wav\r\n\r\n").encode() + open(wav, "rb").read() + \
           f"\r\n--{b}\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--{b}--\r\n".encode()
    return post("http://127.0.0.1:8178/inference", body, f"multipart/form-data; boundary={b}")["text"].strip()


def run(phrase):
    wav = tempfile.mktemp(suffix=".wav")
    subprocess.run(["say", "-o", wav, "--data-format=LEI16@16000", phrase], check=True)
    t = time.perf_counter()
    text = transcribe(wav)
    t1 = time.perf_counter()
    intent = post("http://127.0.0.1:8179/decide",
                  json.dumps({"state": text, "questions": {"intent": INTENTS}}).encode())["answers"]["intent"]
    t2 = time.perf_counter()
    reply = REPLIES[intent["choice"]]
    spoke = post("http://127.0.0.1:8179/speak", json.dumps({"text": reply}).encode()) if reply else None
    t3 = time.perf_counter()
    print(f"{phrase!r:32} heard={text!r:32} intent={intent['choice']}({intent['confidence']:.2f}) "
          f"whisper={1000*(t1-t):.0f}ms laya={1000*(t2-t1):.0f}ms "
          f"tts={1000*(t3-t2):.0f}ms{' cached' if spoke and spoke['cached'] else ''} total={1000*(t3-t):.0f}ms")
    if spoke:
        subprocess.run(["afplay", spoke["wav"]])
    return intent["choice"], t3 - t


if __name__ == "__main__":
    phrases = sys.argv[1:] or ["Hey notch, open up", "Close the notch", "Read this file", "Hey notch, open up"]
    results = [run(p) for p in phrases]
    if not sys.argv[1:]:
        assert [r[0] for r in results] == ["open", "close", "read_file", "open"], results
        assert results[-1][1] < 1.5, "cached reply path must be < 1.5 s"
        print("ok")
