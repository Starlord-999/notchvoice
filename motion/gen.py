"""Generate the NotchVoice motion-graphics promo in two formats from one template.

    python3 gen.py        -> reel/index.html (1080x1920) and wide/index.html (1920x1080)

Footage = twitter-cut/composition/assets/footage.mp4 (real screen recording, X feed blurred).
Clip windows below are in that footage's time.
"""
import json
from pathlib import Path

# Footage clips: (comp_start, duration, media_start)
CLIPS = [(2.4, 3.0, 0.0),    # Hey Notch -> panel -> Open Chrome
         (5.4, 5.5, 4.6),    # Search for latest laptop in 2026 -> results
         (10.9, 3.9, 14.1),  # results -> "Click the first link" -> article
         (14.8, 3.4, 18.1)]  # "Make Chrome full screen" -> full screen

FORMATS = {
    # reel: tall card; the 16:9 footage (zoom box) is wider than the card and pans to follow the action
    "reel": dict(W=1080, H=1920, card=dict(x=40, y=400, w=1000, h=900), zoom_w=1600, pans=[0, 192, 128, 0], notch_zoom=1.75,
                 fs_scale=1.08, fs_y=60, cap_top=1370, wave_top=1630, chip_top=322, chip_left=0, chip_justify="center",
                 hook_size=168, cta_size=150, badge=(3.8, 7.2), cta=(830, 1030, 1190, 1330)),
    "wide": dict(W=1920, H=1080, card=dict(x=300, y=86, w=1320, h=743), zoom_w=1320, pans=[0, 0, 0, 0], notch_zoom=2.3,
                 fs_scale=1.455, fs_y=83, cap_top=872, wave_top=1000, chip_top=16, chip_left=300, chip_justify="flex-start",
                 hook_size=150, cta_size=170, badge=(5.6, 7.2), cta=(400, 620, 745, 870)),
}

TEMPLATE = r"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=__W__, height=__H__" />
    <title>NotchVoice — __FMT__</title>
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { width: __W__px; height: __H__px; overflow: hidden; background: #050607; }
      #root {
        position: relative; width: 100%; height: 100%; overflow: hidden; color: #fff; background: #050607;
        font-family: system-ui, -apple-system, sans-serif; -webkit-font-smoothing: antialiased;
      }
      .clip { position: absolute; inset: 0; }
      .row { position: absolute; left: 0; right: 0; display: flex; justify-content: center; }

      /* Backdrop: breathing glow + fine grain */
      #glow {
        position: absolute; left: -20%; right: -20%; top: -30%; height: 90%;
        background: radial-gradient(closest-side, rgba(52, 199, 89, 0.22), rgba(10, 132, 255, 0.10) 55%, transparent 75%);
        will-change: transform;
      }
      #grain {
        position: absolute; inset: 0; opacity: 0.07; mix-blend-mode: overlay;
        background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' seed='7'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>");
      }

      /* The notch motif, top-center */
      #notch-row { position: absolute; top: 0; left: 0; right: 0; display: flex; justify-content: center; z-index: 20; }
      #notch { width: 250px; height: 46px; background: #000; border-radius: 0 0 18px 18px; position: relative; }
      #notch-ring {
        position: absolute; inset: -6px; border-radius: 0 0 24px 24px; opacity: 0;
        box-shadow: 0 0 36px 8px rgba(52, 199, 89, 0.85), inset 0 0 0 2px rgba(52, 199, 89, 0.9);
      }

      /* Hook */
      #hook .line { overflow: hidden; display: flex; justify-content: center; }
      #hook .line span { display: block; font-size: __HOOK__px; font-weight: 900; letter-spacing: -0.045em; line-height: 1.02; }
      #hook .green { color: #34c759; }
      #hook-stack { position: absolute; left: 0; right: 0; top: 50%; margin-top: -__HOOKHALF__px; }

      /* Screen card with real footage */
      #card {
        position: absolute; left: __CX__px; top: __CY__px; width: __CW__px; height: __CH__px;
        border-radius: 26px; overflow: hidden; background: #000; opacity: 0; z-index: 5;
        box-shadow: 0 40px 120px rgba(0, 0, 0, 0.75), 0 0 0 1.5px rgba(255, 255, 255, 0.12);
        will-change: transform;
      }
      #zoom { position: absolute; top: 0; bottom: 0; left: __ZL__px; width: __ZW__px; will-change: transform; }
      #hide-debug { position: absolute; left: 34.4%; top: 15.9%; width: 11.8%; height: 2.5%; background: #000; opacity: 0; }
      #zoom video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
      #sweep {
        position: absolute; top: -10%; bottom: -10%; left: 0; width: 38%; opacity: 0; z-index: 3;
        background: linear-gradient(90deg, transparent, rgba(52, 199, 89, 0.55), rgba(255, 255, 255, 0.7), rgba(52, 199, 89, 0.55), transparent);
      }

      /* Chapter pill */
      #chips { position: absolute; top: __CHIPTOP__px; left: __CHIPLEFT__px; right: 0; height: 60px; z-index: 6; }
      .chap {
        position: absolute; inset: 0; display: flex; justify-content: __CHIPJUST__; align-items: center; opacity: 0;
      }
      .chap div {
        font-size: 28px; font-weight: 800; letter-spacing: 0.14em; text-transform: uppercase; padding: 10px 24px;
        border-radius: 999px; background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.16); color: rgba(255,255,255,.9);
      }
      .chap b { color: #34c759; margin-right: 12px; }

      /* Kinetic captions (what the user said) */
      #caps { position: absolute; top: __CAPTOP__px; left: 60px; right: 60px; height: 240px; z-index: 6; }
      .cap { position: absolute; inset: 0; display: flex; flex-wrap: wrap; justify-content: center; align-content: flex-start; gap: 0 22px; }
      .cap .wd { display: inline-block; font-size: __CAPSIZE__px; font-weight: 900; letter-spacing: -0.03em; color: rgba(255, 255, 255, 0.45); opacity: 0; }
      .cap .q { color: #34c759; }

      /* Voice waveform */
      #wave { position: absolute; top: __WAVETOP__px; left: 0; right: 0; height: 70px; display: flex; justify-content: center; align-items: center; gap: 9px; z-index: 6; opacity: 0; }
      #wave i { display: block; width: 10px; height: 70px; border-radius: 6px; background: #34c759; transform-origin: 50% 50%; }

      /* Toasts over the card */
      .toast { position: absolute; left: 0; right: 0; bottom: 34px; display: flex; justify-content: center; opacity: 0; z-index: 4; }
      .toast div { font-size: 34px; font-weight: 900; padding: 12px 28px; border-radius: 999px; background: #34c759; color: #03200c; box-shadow: 0 10px 40px rgba(52,199,89,.45); }

      /* First-result chip */
      #result {
        position: absolute; left: 50%; bottom: 110px; width: 760px; margin-left: -380px; z-index: 4; opacity: 0;
        background: #fff; color: #111; border-radius: 22px; padding: 22px 28px; box-shadow: 0 30px 80px rgba(0,0,0,.6);
      }
      #result .k { font-size: 20px; font-weight: 800; color: #1a7f37; letter-spacing: .08em; text-transform: uppercase; }
      #result .u { font-size: 22px; color: #555; margin-top: 6px; }
      #result .t { font-size: 32px; font-weight: 800; color: #1a0dab; margin-top: 4px; }

      /* Stats */
      #stats-title { top: __ST_TITLE__px; }
      #stats-title div { font-size: __ST_TSIZE__px; font-weight: 900; letter-spacing: -0.035em; text-align: center; }
      #stats-title .green { color: #34c759; }
      #tiles { position: absolute; left: 0; right: 0; top: __TILES_TOP__px; display: flex; flex-direction: __TILES_DIR__; align-items: center; justify-content: center; gap: 28px; }
      .tile {
        width: __TILE_W__px; padding: 34px 40px; border-radius: 30px; background: rgba(255,255,255,.06);
        border: 1px solid rgba(255,255,255,.12); opacity: 0;
      }
      .tile .n { font-size: 104px; font-weight: 900; letter-spacing: -0.04em; font-variant-numeric: tabular-nums; }
      .tile .n small { font-size: 46px; color: rgba(255,255,255,.55); margin-left: 8px; font-weight: 800; }
      .tile .l { font-size: 32px; color: rgba(255,255,255,.72); margin-top: 4px; }
      .tile .l b { color: #34c759; }

      /* CTA */
      #badge { position: absolute; left: 50%; top: 50%; width: 250px; height: 46px; margin-left: -125px; margin-top: -__BADGE_MT__px; background: #000; border-radius: 18px; opacity: 0; box-shadow: 0 0 0 1.5px rgba(52,199,89,.6), 0 0 90px rgba(52,199,89,.35); }
      #cta-word { top: __CTA_WORD__px; }
      #cta-word div { font-size: __CTA__px; font-weight: 900; letter-spacing: -0.045em; opacity: 0; }
      #cta-sub { top: __CTA_SUB__px; }
      #cta-sub div { font-size: 40px; color: rgba(255,255,255,.75); opacity: 0; }
      #cta-url { top: __CTA_URL__px; }
      #cta-url div { font-size: __URL_SIZE__px; font-weight: 800; font-family: ui-monospace, Menlo, monospace; color: #fff; padding: 18px 30px; border-radius: 18px; background: rgba(255,255,255,.08); border: 1px solid rgba(255,255,255,.16); opacity: 0; }
      #cta-btn { top: __CTA_BTN__px; }
      #cta-btn div { font-size: 58px; font-weight: 900; padding: 22px 56px; border-radius: 999px; background: #34c759; color: #03200c; opacity: 0; box-shadow: 0 16px 60px rgba(52,199,89,.5); }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-width="__W__" data-height="__H__" data-duration="25">
      <div id="glow"></div>

      <!-- 1 · Hook -->
      <section id="hook" class="clip" data-start="0" data-duration="2.5" data-track-index="1">
        <div id="hook-stack">
          <div class="line"><span id="h1">Your <span class="green" style="display:inline">notch</span></span></div>
          <div class="line"><span id="h2">can hear</span></div>
          <div class="line"><span id="h3">you.</span></div>
        </div>
      </section>

      <!-- 2-5 · Real footage in a floating screen -->
      <div id="card">
        <div id="zoom">
__VIDEOS__
          <div id="hide-debug"></div>
        </div>
        <div id="sweep"></div>
        <div id="toast1" class="toast"><div>✓ Searched Google</div></div>
        <div id="toast2" class="toast"><div>✓ Opened the 1st result</div></div>
        <div id="toast3" class="toast"><div>✓ Full screen</div></div>
        <div id="result">
          <div class="k">1st result · opened by voice</div>
          <div class="u">team-bhp.com</div>
          <div class="t">Quick review of my new Apple MacBook Air M4</div>
        </div>
      </div>

      <div id="chips">
        <div class="chap" id="chap1"><div><b>01</b>Wake</div></div>
        <div class="chap" id="chap2"><div><b>02</b>Search</div></div>
        <div class="chap" id="chap3"><div><b>03</b>Click</div></div>
        <div class="chap" id="chap4"><div><b>04</b>Control</div></div>
      </div>

      <div id="caps">
        <div class="cap" id="cap1"><span class="wd q">“Hey</span><span class="wd q">Notch”</span></div>
        <div class="cap" id="cap2"><span class="wd">“Open</span><span class="wd">Chrome”</span></div>
        <div class="cap" id="cap3"><span class="wd">“Search</span><span class="wd">for</span><span class="wd">latest</span><span class="wd">laptop</span><span class="wd">in</span><span class="wd">2026”</span></div>
        <div class="cap" id="cap4"><span class="wd">“Click</span><span class="wd">the</span><span class="wd">first</span><span class="wd">link”</span></div>
        <div class="cap" id="cap5"><span class="wd">“Make</span><span class="wd">Chrome</span><span class="wd">full</span><span class="wd">screen”</span></div>
        <div class="cap" id="cap6"><span class="wd">No</span><span class="wd">keyboard.</span><span class="wd q">No</span><span class="wd q">mouse.</span></div>
      </div>
      <div id="wave">__BARS__</div>

      <!-- 6 · Stats -->
      <section id="stats" class="clip" data-start="18.2" data-duration="3.5" data-track-index="1">
        <div id="stats-title" class="row"><div>Runs <span class="green">100%</span> on your Mac.</div></div>
        <div id="tiles">
          <div class="tile" id="t1"><div class="n"><span id="n1">0</span><small>ms</small></div><div class="l"><b>Whisper</b> hears you</div></div>
          <div class="tile" id="t2"><div class="n"><span id="n2">0</span><small>ms</small></div><div class="l"><b>Laya-MLX</b> decides</div></div>
          <div class="tile" id="t3"><div class="n"><span id="n3">0</span><small>bytes</small></div><div class="l">sent to the <b>cloud</b></div></div>
        </div>
      </section>

      <!-- 7 · CTA -->
      <section id="cta" class="clip" data-start="21.6" data-duration="3.4" data-track-index="1">
        <div id="badge"></div>
        <div id="cta-word" class="row"><div>NotchVoice</div></div>
        <div id="cta-sub" class="row"><div>Talk to your Mac. Free &amp; open source.</div></div>
        <div id="cta-url" class="row"><div>github.com/Starlord-999/notchvoice</div></div>
        <div id="cta-btn" class="row"><div>Link below ↓</div></div>
      </section>

      <div id="notch-row"><div id="notch"><div id="notch-ring"></div></div></div>
      <div id="grain"></div>

      <!-- Audio -->
__AUDIO__
    </div>

    <script>
      const CFG = __CFG__;
      const tl = gsap.timeline({ paused: true });
      const q = (s) => Array.from(document.querySelectorAll(s));

      // Backdrop breathes slowly (finite)
      tl.fromTo("#glow", { scale: 1, opacity: 0.9 }, { scale: 1.12, opacity: 1, duration: 3, yoyo: true, repeat: 7, ease: "sine.inOut" }, 0);

      // Notch pulse helper
      const pulse = (t) => tl.fromTo("#notch-ring", { opacity: 1, scale: 1 }, { opacity: 0, scale: 1.25, duration: 0.6, ease: "power2.out", immediateRender: false }, t);

      // ── 1 · Hook: three lines slam up through masks, the notch pulses on each
      [["#h1", 0.12], ["#h2", 0.62], ["#h3", 1.12]].forEach(([id, t]) => {
        tl.fromTo(id, { yPercent: 115 }, { yPercent: 0, duration: 0.42, ease: "power4.out" }, t);
        pulse(t);
      });
      tl.fromTo("#hook-stack", { scale: 1 }, { scale: 1.06, duration: 2.1, ease: "none" }, 0.1);
      tl.to("#hook-stack", { opacity: 0, scale: 0.9, filter: "blur(12px)", duration: 0.3, ease: "power2.in" }, 2.15);

      // ── Card enters with a 3D rise
      tl.fromTo("#card", { opacity: 0, y: 160, rotationX: 28, scale: 0.86, transformPerspective: 1600 },
                         { opacity: 1, y: 0, rotationX: 0, scale: 1, duration: 0.7, ease: "power4.out" }, 2.35);

      // Camera inside the card (zoom wrapper): notch panel close-up, then out
      tl.set("#zoom", { scale: CFG.notchZoom, x: CFG.pans[0], transformOrigin: "50% 6%" }, 2.35);
      [[5.4, 1], [10.9, 2], [14.8, 3]].forEach(([t, i]) => tl.to("#zoom", { x: CFG.pans[i], duration: 0.45, ease: "power3.inOut" }, t - 0.05));
      tl.set("#hide-debug", { opacity: 1 }, 3.2);
      tl.set("#hide-debug", { opacity: 0 }, 5.45);
      tl.to("#zoom", { scale: 1, duration: 0.7, ease: "power3.inOut" }, 4.75);
      tl.to("#zoom", { scale: 1.28, transformOrigin: "42% 42%", duration: 1.3, ease: "power2.out" }, 9.75);   // laptop results
      tl.to("#zoom", { scale: 1, duration: 0.35, ease: "power2.inOut" }, 10.85);
      tl.to("#zoom", { scale: 1.16, transformOrigin: "45% 72%", duration: 0.9, ease: "power2.out" }, 14.2);  // article
      tl.to("#zoom", { scale: 1, duration: 0.3, ease: "power2.inOut" }, 14.8);

      // Light sweep across the card on every cut
      [5.35, 10.85, 14.75].forEach((t) => tl.fromTo("#sweep", { xPercent: -120, opacity: 1 }, { xPercent: 320, opacity: 1, duration: 0.45, ease: "power2.inOut", immediateRender: false }, t));
      tl.set("#sweep", { opacity: 0 }, 15.3);

      // Full-screen moment: the card itself goes full-bleed
      tl.to("#card", { scale: CFG.fs_scale, y: CFG.fs_y, borderRadius: 0, duration: 0.55, ease: "power4.inOut" }, 17.3);
      // Card leaves for the stats
      tl.to("#card", { opacity: 0, scale: CFG.fs_scale * 0.92, filter: "blur(10px)", duration: 0.4, ease: "power2.in" }, 18.0);

      // Chapters
      const chap = (id, a, b) => {
        tl.fromTo(id, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.3, ease: "power3.out" }, a);
        tl.to(id, { opacity: 0, y: -10, duration: 0.2 }, b);
      };
      chap("#chap1", 2.6, 5.3); chap("#chap2", 5.5, 10.8); chap("#chap3", 11.0, 14.7); chap("#chap4", 14.9, 17.7);

      // Kinetic captions: words appear dim, light up as they're spoken
      const say = (id, show, words, end) => {
        const ws = q(id + " .wd");
        tl.fromTo(ws, { opacity: 0, y: 26 }, { opacity: 1, y: 0, duration: 0.25, stagger: 0.03, ease: "power3.out" }, show);
        ws.forEach((w, i) => {
          const t = words[Math.min(i, words.length - 1)];
          tl.fromTo(w, { color: w.classList.contains("q") ? "#34c759" : "rgba(255,255,255,0.45)", scale: 1 },
                       { color: w.classList.contains("q") ? "#34c759" : "#ffffff", scale: 1.08, duration: 0.12, ease: "power2.out", immediateRender: false }, t);
          tl.to(w, { scale: 1, duration: 0.2 }, t + 0.12);
        });
        tl.to(ws, { opacity: 0, y: -18, duration: 0.2, stagger: 0.02 }, end);
      };
      say("#cap1", 2.45, [2.55, 2.8], 3.5);
      say("#cap2", 3.55, [3.62, 3.95], 5.25);
      say("#cap3", 5.45, [5.6, 6.1, 6.55, 7.1, 7.7, 8.2], 9.7);
      say("#cap6", 9.8, [9.85, 10.2, 10.55, 10.9], 11.5);
      say("#cap4", 11.6, [11.95, 12.15, 12.35, 12.55], 13.8);
      say("#cap5", 14.85, [14.95, 15.3, 15.65, 16.0], 17.2);

      // Waveform while the user is speaking
      const bars = q("#wave i");
      const talk = (a, b) => {
        tl.to("#wave", { opacity: 1, duration: 0.15 }, a);
        const n = Math.max(1, Math.round((b - a) / 0.36));
        bars.forEach((bar, i) => {
          const h = 0.35 + ((i * 37) % 10) / 14;
          tl.fromTo(bar, { scaleY: 0.18 }, { scaleY: h, duration: 0.18, yoyo: true, repeat: n * 2 - 1, ease: "sine.inOut", immediateRender: false }, a + (i % 4) * 0.03);
        });
        tl.to("#wave", { opacity: 0.25, duration: 0.2 }, b);
      };
      tl.set(bars, { scaleY: 0.18 }, 0);
      talk(2.5, 2.95); talk(3.6, 4.6); talk(5.55, 8.95); talk(11.9, 12.7); talk(14.9, 16.4);
      tl.to("#wave", { opacity: 0, duration: 0.2 }, 17.9);

      // Toasts + result chip
      const pop = (id, a, b) => {
        tl.fromTo(id, { opacity: 0, y: 30, scale: 0.9 }, { opacity: 1, y: 0, scale: 1, duration: 0.3, ease: "back.out(2.2)" }, a);
        tl.to(id, { opacity: 0, y: 12, duration: 0.2 }, b);
      };
      pop("#toast1", 9.75, 10.8);
      pop("#toast2", 14.25, 14.75);
      pop("#toast3", 17.45, 18.0);
      tl.fromTo("#result", { opacity: 0, y: 60, rotationX: -30, transformPerspective: 1200 }, { opacity: 1, y: 0, rotationX: 0, duration: 0.45, ease: "power4.out" }, 12.9);
      tl.to("#result", { opacity: 0, y: -40, scale: 0.95, duration: 0.3 }, 14.05);

      // ── 6 · Stats: title, tiles rise, counters roll
      tl.fromTo("#stats-title div", { opacity: 0, y: 40 }, { opacity: 1, y: 0, duration: 0.45, ease: "power4.out" }, 18.3);
      tl.fromTo(".tile", { opacity: 0, y: 70, scale: 0.92 }, { opacity: 1, y: 0, scale: 1, duration: 0.45, stagger: 0.14, ease: "power4.out" }, 18.65);
      const count = (id, to, t) => {
        const o = { v: 0 }, el = document.getElementById(id);
        tl.fromTo(o, { v: 0 }, { v: to, duration: 0.9, ease: "power2.out", onUpdate: () => { el.textContent = Math.round(o.v); } }, t);
      };
      count("n1", 110, 18.75); count("n2", 25, 18.9);
      tl.fromTo("#t3", { borderColor: "rgba(255,255,255,0.12)" }, { borderColor: "rgba(52,199,89,0.9)", duration: 0.3 }, 19.3);
      tl.to(["#stats-title div", ".tile"], { opacity: 0, y: -30, duration: 0.3, stagger: 0.04 }, 21.3);

      // ── 7 · CTA: the notch drops, becomes the badge, the name lands on the beat
      tl.fromTo("#badge", { opacity: 0, y: -CFG.badgeDrop, scale: 1 }, { opacity: 1, y: 0, duration: 0.45, ease: "power3.inOut" }, 21.7);
      tl.to("#badge", { scaleX: CFG.badgeSX, scaleY: CFG.badgeSY, borderRadius: 30, duration: 0.5, ease: "power4.out" }, 22.15);
      pulse(22.2);
      // beat-locked: 22.65s — wordmark
      tl.fromTo("#cta-word div", { opacity: 0, scale: 0.85, y: 20 }, { opacity: 1, scale: 1, y: 0, duration: 0.45, ease: "back.out(1.6)" }, 22.6);
      tl.fromTo("#cta-sub div", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.4 }, 23.0);
      tl.fromTo("#cta-url div", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.4 }, 23.25);
      tl.fromTo("#cta-btn div", { opacity: 0, scale: 0.8 }, { opacity: 1, scale: 1, duration: 0.4, ease: "back.out(2.4)" }, 23.5);
      tl.to("#cta-btn div", { y: 14, duration: 0.28, yoyo: true, repeat: 3, ease: "sine.inOut" }, 23.95);

      window.__timelines["main"] = tl;
    </script>
  </body>
</html>
"""


def build(fmt, c):
    card = c["card"]
    videos = "\n".join(
        f'          <video id="v{i}" src="assets/footage.mp4" data-start="{s}" data-duration="{d}" data-media-start="{m}" data-track-index="0" muted playsinline></video>'
        for i, (s, d, m) in enumerate(CLIPS, 1))
    audio = [f'      <audio id="fa{i}" src="assets/footage-audio.m4a" data-start="{s}" data-duration="{d}" data-media-start="{m}" data-track-index="10" data-volume="1"></audio>'
             for i, (s, d, m) in enumerate(CLIPS, 1)]
    music_auto = json.dumps({"version": 1, "lanes": [{"target": "volume", "points": [
        {"t": 0, "v": 0.55}, {"t": 2.2, "v": 0.55}, {"t": 2.6, "v": 0.16}, {"t": 17.9, "v": 0.16},
        {"t": 18.3, "v": 0.5}, {"t": 24.2, "v": 0.5}, {"t": 25, "v": 0}]}]})
    audio += [
        f"      <audio id=\"music\" src=\"assets/music/happy-beats-business-moves-vol-11-by-ende-dot-app.mp3\" data-start=\"0\" data-duration=\"25\" data-track-index=\"11\" data-volume=\"0.5\" data-automation='{music_auto}'></audio>",
        '      <audio id="vo1" src="assets/vo/nokeyboard.wav" data-start="9.85" data-duration="1.69" data-track-index="12" data-volume="1"></audio>',
        '      <audio id="vo2" src="assets/vo/cta.wav" data-start="22.7" data-duration="2.07" data-track-index="12" data-volume="1"></audio>',
    ]
    sfx = [("s1", "impactSoft_medium_001.ogg", 0.12, 0.18, 0.7), ("s2", "impactSoft_medium_003.ogg", 0.62, 0.14, 0.7),
           ("s3", "impactSoft_heavy_003.ogg", 1.12, 0.54, 0.6), ("s4", "card-slide-1.ogg", 2.35, 0.6, 0.45),
           ("s5", "click_003.ogg", 9.75, 0.02, 0.7), ("s6", "click_003.ogg", 14.25, 0.02, 0.7),
           ("s7", "impactSoft_medium_001.ogg", 17.3, 0.18, 0.6), ("s8", "click_003.ogg", 17.45, 0.02, 0.6),
           ("s9", "impactBell_heavy_000.ogg", 22.6, 1.48, 0.5)]
    audio += [f'      <audio id="{i}" src="assets/sfx/{f}" data-start="{t}" data-duration="{d}" data-track-index="{13 + n % 2}" data-volume="{v}"></audio>'
              for n, (i, f, t, d, v) in enumerate(sfx)]

    reel = fmt == "reel"
    cfg = dict(fs_scale=c["fs_scale"], fs_y=c["fs_y"], badgeDrop=c["H"] / 2 - 23, pans=c["pans"], notchZoom=c["notch_zoom"],
               badgeSX=c["badge"][0], badgeSY=c["badge"][1])
    subs = {
        "__W__": c["W"], "__H__": c["H"], "__FMT__": fmt,
        "__CX__": card["x"], "__CY__": card["y"], "__CW__": card["w"], "__CH__": card["h"],
        "__HOOK__": c["hook_size"], "__HOOKHALF__": int(c["hook_size"] * 1.53),
        "__CAPTOP__": c["cap_top"], "__CAPSIZE__": 76 if reel else 60, "__WAVETOP__": c["wave_top"], "__CHIPTOP__": c["chip_top"],
        "__ST_TITLE__": 330 if reel else 150, "__ST_TSIZE__": 92 if reel else 96,
        "__TILES_TOP__": 560 if reel else 390, "__TILES_DIR__": "column" if reel else "row", "__TILE_W__": 840 if reel else 480,
        "__BADGE_MT__": 23, "__CTA__": c["cta_size"],
        "__CTA_WORD__": c["cta"][0], "__CTA_SUB__": c["cta"][1],
        "__CTA_URL__": c["cta"][2], "__URL_SIZE__": 38 if reel else 40, "__CTA_BTN__": c["cta"][3],
        "__ZL__": (card["w"] - c["zoom_w"]) // 2, "__ZW__": c["zoom_w"],
        "__CHIPLEFT__": c["chip_left"], "__CHIPJUST__": c["chip_justify"],
        "__VIDEOS__": videos, "__AUDIO__": "\n".join(audio), "__BARS__": "<i></i>" * 16, "__CFG__": json.dumps(cfg),
    }
    html = TEMPLATE
    for k, v in subs.items():
        html = html.replace(k, str(v))
    Path(__file__).parent.joinpath(fmt, "index.html").write_text(html)


for fmt, c in FORMATS.items():
    build(fmt, c)
    print("wrote", fmt)
