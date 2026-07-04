/* SERVO PROTOCOL | machine terminal interactions */

// ------------------------------------------------------------ receipt ticker
// Rendered twice so the CSS -50% translate loops seamlessly.
const RECEIPTS = [
  "RCPT#0492 | MID-0002 -> MID-0001 | <b>CHARGING</b> | 5.00 USDC | bay A-07 | settled",
  "RCPT#0493 | MID-0117 -> MID-0033 | <b>COMPUTE</b> | 1.20 USDC | burst 9ms | settled",
  "RCPT#0494 | MID-0021 -> MID-0117 | <b>MAP_DATA</b> | 0.35 USDC | tile 88:41 | settled",
  "RCPT#0495 | MID-0002 -> MID-0090 | <b>TOLL</b> | 0.85 USDC | route 7 | settled",
  "RCPT#0496 | MID-0033 -> MID-0001 | <b>CHARGING</b> | 5.00 USDC | bay C-02 | settled",
  "RCPT#0497 | MID-0090 -> MID-0117 | <b>SENSOR_FEED</b> | 0.12 USDC | lidar 4s | settled",
  "RCPT#0498 | MID-0017 -> MID-0044 | <b>DOCKING</b> | 2.10 USDC | port 12 | settled",
  "TX DENIED | MID-0002 | DailyCapExceeded | attempted 5.00 | remaining 0.00",
  "RCPT#0499 | MID-0044 -> MID-0001 | <b>CHARGING</b> | 5.00 USDC | bay A-03 | settled",
  "RCPT#0500 | MID-0117 -> MID-0021 | <b>TASK_HANDOFF</b> | 3.40 USDC | pkg 7781 | settled",
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
