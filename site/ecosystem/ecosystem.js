// SERVO OS — boot sequence, clock, and hover-driven dependency lines.

const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---------------------------------------------------------------- boot
const boot = document.getElementById("boot");
const bootInner = document.getElementById("bootInner");

const BOOT_LINES = [
  "SERVO OS v0.1",
  "",
  "> mounting machine registry .......... <ok>OK</ok>",
  "> connecting to robinhood chain ...... <ok>OK</ok>",
  "> loading modules ................... 11 found",
  "> 5 live &middot; 3 in build &middot; 3 planned",
];

function dismissBoot() {
  boot.classList.add("gone");
  setTimeout(() => boot.remove(), 600);
}
boot.addEventListener("click", dismissBoot);

async function runBoot() {
  if (reduce) {
    bootInner.innerHTML =
      BOOT_LINES.map((l) => `<div class="boot-line">${l}</div>`).join("") +
      '<div class="boot-ready">READY</div>';
    setTimeout(dismissBoot, 500);
    return;
  }
  for (const line of BOOT_LINES) {
    const el = document.createElement("div");
    el.className = "boot-line";
    el.innerHTML = line;
    bootInner.appendChild(el);
    await sleep(line ? 230 : 90);
  }
  const ready = document.createElement("div");
  ready.className = "boot-ready cursor";
  ready.textContent = "READY";
  bootInner.appendChild(ready);
  await sleep(700);
  dismissBoot();
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
runBoot();

// ---------------------------------------------------------------- clock
const clockEl = document.getElementById("clock");
function tick() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  clockEl.textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())} UTC${d.getTimezoneOffset() <= 0 ? "+" : "-"}${Math.abs(d.getTimezoneOffset() / 60)}`;
}
tick();
setInterval(tick, 1000);

// ---------------------------------------------------------------- dependency lines
const map = document.getElementById("map");
const svg = document.getElementById("links");
const mods = [...document.querySelectorAll(".mod")];
const byId = {};
mods.forEach((m) => (byId[m.dataset.id] = m));

function centerTop(el, rect) {
  const r = el.getBoundingClientRect();
  return { x: r.left - rect.left + r.width / 2, y: r.top - rect.top };
}
function centerBottom(el, rect) {
  const r = el.getBoundingClientRect();
  return { x: r.left - rect.left + r.width / 2, y: r.bottom - rect.top };
}

function clearLines() {
  svg.innerHTML = "";
  map.classList.remove("focusing");
  mods.forEach((m) => m.classList.remove("hot", "dep"));
}

function showDeps(mod) {
  clearLines(); // reset any prior hover so paths never accumulate
  const deps = (mod.dataset.deps || "").split(" ").filter(Boolean);
  const rect = map.getBoundingClientRect();
  map.classList.add("focusing");
  mod.classList.add("hot");

  const from = centerTop(mod, rect); // draw upward from the top of the hovered module
  for (const id of deps) {
    const target = byId[id];
    if (!target) continue;
    target.classList.add("dep");
    const to = centerBottom(target, rect);
    const midY = (from.y + to.y) / 2;
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", `M ${from.x} ${from.y} C ${from.x} ${midY}, ${to.x} ${midY}, ${to.x} ${to.y}`);
    path.setAttribute("class", "link-path on");
    svg.appendChild(path);
  }
}

mods.forEach((mod) => {
  mod.addEventListener("mouseenter", () => showDeps(mod));
  mod.addEventListener("mouseleave", clearLines);
  // keyboard focus support
  mod.addEventListener("focusin", () => showDeps(mod));
  mod.addEventListener("focusout", clearLines);
});
window.addEventListener("resize", clearLines);
