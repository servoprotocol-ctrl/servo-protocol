/* SERVO PROTOCOL | hero dot-matrix robot
   Samples assets/robot-hero.png into a field of dots ("every dot is a receipt"),
   assembles them on load, and lets the cursor push through them.
   Static single frame under prefers-reduced-motion. */

(function () {
  "use strict";

  const canvas = document.getElementById("heroDots");
  if (!canvas || !canvas.getContext) return;

  const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const ctx = canvas.getContext("2d");
  const IMG_SRC = "assets/robot-hero.png";

  // luminance ramp: dim forest -> lime -> pale highlight (brand palette)
  const RAMP = ["#1c3823", "#2e5c31", "#47913c", "#66c24d", "#8cff66", "#c9ffae"];
  const SIZES = 3; // quantized sprite sizes per color

  let dpr = Math.min(window.devicePixelRatio || 1, 2);
  let W = 0, H = 0;              // CSS px
  let dots = [];                 // particle field
  let sprites = [];              // [color][size] pre-rendered dot sprites
  let spriteR = [];              // radius for each size bucket
  let running = false;
  let assembled = false;
  let visible = true;
  let raf = 0;
  let t0 = 0;
  const pointer = { x: -9999, y: -9999, active: false };

  // ---------------------------------------------------------- sprites
  function buildSprites(stepPx) {
    sprites = [];
    spriteR = [];
    for (let s = 0; s < SIZES; s++) {
      spriteR.push(stepPx * (0.26 + s * 0.09));
    }
    for (let c = 0; c < RAMP.length; c++) {
      const row = [];
      for (let s = 0; s < SIZES; s++) {
        const r = spriteR[s];
        const size = Math.ceil((r * 2 + 4) * dpr);
        const sc = document.createElement("canvas");
        sc.width = size;
        sc.height = size;
        const sctx = sc.getContext("2d");
        sctx.scale(dpr, dpr);
        sctx.fillStyle = RAMP[c];
        sctx.beginPath();
        sctx.arc(size / (2 * dpr), size / (2 * dpr), r, 0, Math.PI * 2);
        sctx.fill();
        row.push(sc);
      }
      sprites.push(row);
    }
  }

  // find the image's non-transparent bounding box (so the robot fills the frame)
  function alphaBBox(img) {
    const probe = document.createElement("canvas");
    const pw = 160, ph = Math.max(1, Math.round((img.height / img.width) * 160));
    probe.width = pw;
    probe.height = ph;
    const pctx = probe.getContext("2d", { willReadFrequently: true });
    pctx.drawImage(img, 0, 0, pw, ph);
    let data;
    try { data = pctx.getImageData(0, 0, pw, ph).data; } catch (e) { return null; }
    let x0 = pw, y0 = ph, x1 = 0, y1 = 0, found = false;
    for (let y = 0; y < ph; y++) {
      for (let x = 0; x < pw; x++) {
        if (data[(y * pw + x) * 4 + 3] > 40) {
          found = true;
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (!found) return null;
    const fx = img.width / pw, fy = img.height / ph;
    return { sx: x0 * fx, sy: y0 * fy, sw: (x1 - x0 + 1) * fx, sh: (y1 - y0 + 1) * fy };
  }

  // ---------------------------------------------------------- sampling
  function sample(img) {
    const rect = canvas.getBoundingClientRect();
    W = Math.max(280, Math.round(rect.width));
    H = Math.max(280, Math.round(rect.height));
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    // crop to the robot itself, then fit (contain) with a small margin
    const box = alphaBBox(img) || { sx: 0, sy: 0, sw: img.width, sh: img.height };
    const pad = W * 0.02;
    const availW = W - pad * 2, availH = H - pad * 2;
    const scale = Math.min(availW / box.sw, availH / box.sh);
    const iw = box.sw * scale, ih = box.sh * scale;
    const ix = (W - iw) / 2, iy = (H - ih) / 2;

    const off = document.createElement("canvas");
    off.width = W;
    off.height = H;
    const octx = off.getContext("2d", { willReadFrequently: true });
    octx.drawImage(img, box.sx, box.sy, box.sw, box.sh, ix, iy, iw, ih);

    let data;
    try {
      data = octx.getImageData(0, 0, W, H).data;
    } catch (e) {
      return false; // tainted canvas (file://) — fall back to plain image
    }

    const step = Math.max(4, Math.round(W / 104));
    buildSprites(step);

    // first pass: collect luminance range so a dark render still spans the ramp
    const pts = [];
    let lumMin = 1, lumMax = 0;
    for (let y = 0; y < H; y += step) {
      for (let x = 0; x < W; x += step) {
        const i = (y * W + x) * 4;
        const a = data[i + 3];
        if (a < 110) continue;
        const lum = (0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255;
        if (lum < lumMin) lumMin = lum;
        if (lum > lumMax) lumMax = lum;
        pts.push({ x, y, lum });
      }
    }
    if (!pts.length) return false;
    const span = Math.max(0.0001, lumMax - lumMin);

    dots = pts.map((p, i) => {
      let n = (p.lum - lumMin) / span;   // 0..1 normalized
      n = Math.pow(n, 0.45);             // lift midtones
      const ci = Math.min(RAMP.length - 1, Math.floor(n * RAMP.length));
      const si = Math.min(SIZES - 1, Math.floor(n * SIZES));
      const ang = Math.random() * Math.PI * 2;
      const dist = 60 + Math.random() * 180;
      return {
        ox: p.x, oy: p.y,                 // home
        x: p.x + Math.cos(ang) * dist,    // scattered start
        y: p.y + Math.sin(ang) * dist,
        vx: 0, vy: 0,
        ci, si,
        baseA: 0.62 + n * 0.38,
        phase: Math.random() * Math.PI * 2,
        delay: (p.y / H) * 520 + Math.random() * 240, // top-to-bottom sweep
      };
    });
    return true;
  }

  // ---------------------------------------------------------- physics + draw
  const SPRING = 0.02;
  const DAMP = 0.885;
  const REACT_R = 150;
  const PUSH = 14;
  const ASSEMBLE_MS = 950;

  function frame(now) {
    raf = 0;
    if (!running) return;
    const t = now - t0;
    ctx.clearRect(0, 0, W, H);

    const bobY = Math.sin(now * 0.0005) * 5; // gentle float of the whole machine
    const scanY = ((now % 5600) / 5600) * (H + 160) - 80; // sweeping scan band

    const px = pointer.x, py = pointer.y - bobY;
    const pActive = pointer.active;

    let settled = assembled;

    for (let i = 0; i < dots.length; i++) {
      const d = dots[i];

      if (!assembled) {
        // assemble: ease each dot home after its delay
        const k = Math.min(1, Math.max(0, (t - d.delay) / ASSEMBLE_MS));
        const e = 1 - Math.pow(1 - k, 3);
        d.x += (d.ox - d.x) * e * 0.28;
        d.y += (d.oy - d.y) * e * 0.28;
        if (k < 1) settled = false;
      } else {
        // cursor repulsion
        if (pActive) {
          const dx = d.x - px, dy = d.y - py;
          const dist2 = dx * dx + dy * dy;
          if (dist2 < REACT_R * REACT_R && dist2 > 0.01) {
            const dist = Math.sqrt(dist2);
            const f = Math.pow(1 - dist / REACT_R, 2) * PUSH;
            d.vx += (dx / dist) * f;
            d.vy += (dy / dist) * f;
          }
        }
        // spring home + damping
        d.vx += (d.ox - d.x) * SPRING;
        d.vy += (d.oy - d.y) * SPRING;
        d.vx *= DAMP;
        d.vy *= DAMP;
        d.x += d.vx;
        d.y += d.vy;
      }

      // shimmer + scan band highlight
      let alpha = d.baseA * (0.84 + 0.16 * Math.sin(now * 0.0016 + d.phase));
      let si = d.si;
      const scanD = Math.abs(d.oy - scanY);
      if (scanD < 24) {
        alpha = Math.min(1, alpha + (1 - scanD / 24) * 0.5);
        if (si < SIZES - 1) si++;
      }

      const sp = sprites[d.ci][si];
      const half = sp.width / (2 * dpr);
      ctx.globalAlpha = alpha;
      ctx.drawImage(sp, d.x - half, d.y - half + bobY, sp.width / dpr, sp.height / dpr);
    }
    ctx.globalAlpha = 1;

    if (!assembled && settled && t > ASSEMBLE_MS) {
      assembled = true;
      const hint = document.getElementById("heroHint");
      if (hint) hint.classList.add("show");
    }
    if (visible) raf = requestAnimationFrame(frame);
  }

  function drawStatic() {
    ctx.clearRect(0, 0, W, H);
    for (let i = 0; i < dots.length; i++) {
      const d = dots[i];
      const sp = sprites[d.ci][d.si];
      const half = sp.width / (2 * dpr);
      ctx.globalAlpha = d.baseA;
      ctx.drawImage(sp, d.ox - half, d.oy - half, sp.width / dpr, sp.height / dpr);
    }
    ctx.globalAlpha = 1;
    const hint = document.getElementById("heroHint");
    if (hint) hint.classList.add("show");
  }

  function start() {
    if (running || REDUCED) return;
    running = true;
    t0 = performance.now();
    raf = requestAnimationFrame(frame);
  }

  // ---------------------------------------------------------- wiring
  function fallbackImg() {
    const img = document.createElement("img");
    img.src = IMG_SRC;
    img.alt = "";
    img.className = "hero-robot-fallback";
    canvas.replaceWith(img);
  }

  const image = new Image();
  image.onload = function () {
    if (!sample(image)) { fallbackImg(); return; }

    if (REDUCED) {
      // no motion: dots sit at home, one frame
      dots.forEach((d) => { d.x = d.ox; d.y = d.oy; });
      drawStatic();
      return;
    }

    start();

    // pointer interaction (mouse + touch) — tracked on the whole hero visual
    // so the dots react the moment the cursor gets anywhere near the machine
    const zone = canvas.parentElement || canvas;
    const updatePointer = (e) => {
      const r = canvas.getBoundingClientRect();
      pointer.x = e.clientX - r.left;
      pointer.y = e.clientY - r.top;
      pointer.active = true;
    };
    zone.addEventListener("pointermove", updatePointer);
    zone.addEventListener("pointerdown", updatePointer);
    zone.addEventListener("pointerleave", () => { pointer.active = false; });
    zone.addEventListener("pointercancel", () => { pointer.active = false; });

    // pause offscreen / hidden tab
    const io = new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      if (visible && running && !raf) raf = requestAnimationFrame(frame);
    }, { threshold: 0.05 });
    io.observe(canvas);

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden && running && !raf && visible) {
        raf = requestAnimationFrame(frame);
      }
    });

    // rebuild on meaningful resize (keeps grid density right)
    let lastW = canvas.clientWidth;
    let resizeTimer = 0;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        if (Math.abs(canvas.clientWidth - lastW) < 24) return;
        lastW = canvas.clientWidth;
        dpr = Math.min(window.devicePixelRatio || 1, 2);
        const wasAssembled = assembled;
        if (sample(image) && wasAssembled) {
          dots.forEach((d) => { d.x = d.ox; d.y = d.oy; });
        }
      }, 180);
    });
  };
  image.onerror = fallbackImg;
  image.src = IMG_SRC;
})();
