/* SERVO PROTOCOL | machine terminal interactions */

// ------------------------------------------------------------ receipt ticker
// Rendered twice so the CSS -50% translate loops seamlessly.
const RECEIPTS = [
  "RCPT#0492 | MID-0002 -> MID-0001 | <b>CHARGING</b> | 5.00 USDG | bay A-07 | settled",
  "RCPT#0493 | MID-0117 -> MID-0033 | <b>COMPUTE</b> | 1.20 USDG | burst 9ms | settled",
  "RCPT#0494 | MID-0021 -> MID-0117 | <b>MAP_DATA</b> | 0.35 USDG | tile 88:41 | settled",
  "RCPT#0495 | MID-0002 -> MID-0090 | <b>TOLL</b> | 0.85 USDG | route 7 | settled",
  "RCPT#0496 | MID-0033 -> MID-0001 | <b>CHARGING</b> | 5.00 USDG | bay C-02 | settled",
  "RCPT#0497 | MID-0090 -> MID-0117 | <b>SENSOR_FEED</b> | 0.12 USDG | lidar 4s | settled",
  "RCPT#0498 | MID-0017 -> MID-0044 | <b>DOCKING</b> | 2.10 USDG | port 12 | settled",
  "TX DENIED | MID-0002 | DailyCapExceeded | attempted 5.00 | remaining 0.00",
  "RCPT#0499 | MID-0044 -> MID-0001 | <b>CHARGING</b> | 5.00 USDG | bay A-03 | settled",
  "RCPT#0500 | MID-0117 -> MID-0021 | <b>TASK_HANDOFF</b> | 3.40 USDG | pkg 7781 | settled",
];

const track = document.getElementById("tickerTrack");
if (track) {
  const items = RECEIPTS.map((r) => `<span>${r}</span>`).join("");
  track.innerHTML = items + items;
}

// ------------------------------------------------------------ reveal on scroll
const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add("in");
        revealObserver.unobserve(e.target);
      }
    }
  },
  { threshold: 0.12 },
);
document.querySelectorAll(".reveal").forEach((el) => revealObserver.observe(el));

// ------------------------------------------------------------ stat counters
function animateCount(el) {
  const target = parseInt(el.dataset.count, 10);
  const suffix = el.dataset.suffix || "";
  const dur = 1400;
  const start = performance.now();
  function frame(now) {
    const t = Math.min((now - start) / dur, 1);
    const eased = 1 - Math.pow(1 - t, 3);
    el.textContent = Math.round(target * eased) + suffix;
    if (t < 1) requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

const statObserver = new IntersectionObserver(
  (entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        animateCount(e.target);
        statObserver.unobserve(e.target);
      }
    }
  },
  { threshold: 0.5 },
);
document.querySelectorAll(".stat-num").forEach((el) => statObserver.observe(el));

// ------------------------------------------------------------ market simulation
// Payment packets travel buyer -> provider; each arrival logs a receipt.
const SIM_NODES = {
  A: { x: 280, y: 76, label: "CHARGE STATION", mid: "MID-0001" },
  B: { x: 112, y: 292, label: "DELIVERY BOT", mid: "MID-0002" },
  C: { x: 448, y: 292, label: "MAPPING DRONE", mid: "MID-0117" },
};

const SIM_TRADES = [
  { from: "B", to: "A", svc: "CHARGING", amt: "5.00" },
  { from: "B", to: "C", svc: "MAP_DATA", amt: "0.35" },
  { from: "C", to: "A", svc: "CHARGING", amt: "5.00" },
  { from: "A", to: "C", svc: "INSPECTION", amt: "2.40" },
  { from: "C", to: "B", svc: "TASK_HANDOFF", amt: "3.40" },
  { from: "B", to: "A", svc: "DOCKING", amt: "2.10" },
];

const simSvg = document.getElementById("simSvg");
if (simSvg && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const pkt = document.getElementById("simPkt");
  const log = document.getElementById("simLog");
  let tradeIdx = 0;
  let rcpt = 501;

  function nodeEl(key) {
    return document.getElementById("node" + key);
  }

  function runTrade() {
    const t = SIM_TRADES[tradeIdx % SIM_TRADES.length];
    tradeIdx++;
    const from = SIM_NODES[t.from];
    const to = SIM_NODES[t.to];

    nodeEl(t.from).classList.add("hot");
    const start = performance.now();
    const dur = 1300;

    function step(now) {
      const p = Math.min((now - start) / dur, 1);
      const ease = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      pkt.setAttribute("cx", from.x + (to.x - from.x) * ease);
      pkt.setAttribute("cy", from.y + (to.y - from.y) * ease);
      if (p < 1) {
        requestAnimationFrame(step);
      } else {
        nodeEl(t.from).classList.remove("hot");
        const el = nodeEl(t.to);
        el.classList.add("hot");
        setTimeout(() => el.classList.remove("hot"), 700);
        pkt.setAttribute("cx", -20);
        pkt.setAttribute("cy", -20);

        const li = document.createElement("li");
        li.innerHTML =
          "RCPT#0" + rcpt++ + " | " + SIM_NODES[t.from].mid + " → " + SIM_NODES[t.to].mid +
          " | <b>" + t.svc + "</b> | <span class='log-amt'>" + t.amt + " USDG</span> | settled";
        log.prepend(li);
        while (log.children.length > 6) log.removeChild(log.lastChild);
      }
    }
    requestAnimationFrame(step);
  }

  const simObserver = new IntersectionObserver(
    (entries) => {
      if (entries[0].isIntersecting) {
        runTrade();
        setInterval(runTrade, 2600);
        simObserver.disconnect();
      }
    },
    { threshold: 0.3 },
  );
  simObserver.observe(simSvg);
}

// ------------------------------------------------------------ loop step cycler
const loopSteps = document.querySelectorAll(".loop-step");
if (loopSteps.length && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  let loopIdx = 0;
  const loopObserver = new IntersectionObserver(
    (entries) => {
      if (entries[0].isIntersecting) {
        setInterval(() => {
          loopSteps.forEach((s, i) => s.classList.toggle("active", i === loopIdx % loopSteps.length));
          loopIdx++;
        }, 2200);
        loopObserver.disconnect();
      }
    },
    { threshold: 0.3 },
  );
  loopObserver.observe(loopSteps[0]);
}
