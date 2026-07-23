/* SERVO PROTOCOL | machine terminal interactions v2 */

(function () {
  "use strict";

  const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const FINE_POINTER = window.matchMedia("(pointer: fine)").matches;
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

  /* ------------------------------------------------------------ receipt ticker
     Rendered twice so the CSS -50% translate loops seamlessly.
     The ticker tells the whole story: trades, splits, stock claims, denials. */
  const RECEIPTS = [
    "RCPT#0501 | MID-0002 &rarr; MID-0001 | <b>CHARGING</b> | 5.00 USDG | settled",
    "RCPT#0502 | AGT-0007 &rarr; MID-0117 | <b>MAP_DATA</b> | 0.35 USDG | agent paid | settled",
    "SPLIT | sCHG POOL | 0.099 USDG &rarr; 70% OPERATOR / 30% BACKERS | auto",
    "RCPT#0503 | AGT-0003 &rarr; MID-0002 | <b>TASK_HIRE</b> | 3.40 USDG | agent hired robot | settled",
    "CLAIM | MID-0002 | DIVIDEND &rarr; <b>NVDA</b> | swapped on Uniswap v4 | settled",
    "RCPT#0504 | MID-0033 &rarr; MID-0001 | <b>CHARGING</b> | 5.00 USDG | settled",
    "<i>TX DENIED | MID-0002 | DailyCapExceeded | attempted 5.00 | remaining 0.00</i>",
    "RCPT#0505 | MID-0090 &rarr; MID-0117 | <b>SENSOR_FEED</b> | 0.12 USDG | settled",
    "ORACLE | CHAINLINK | USDG/USD = $0.99995 | fresh &#10003;",
    "RCPT#0506 | MID-0117 &rarr; MID-0021 | <b>TASK_HANDOFF</b> | 3.40 USDG | settled",
  ];

  const track = document.getElementById("tickerTrack");
  if (track) {
    const items = RECEIPTS.map((r) => `<span>${r}</span>`).join("");
    track.innerHTML = items + items;
  }

  /* ------------------------------------------------------------ reveal on scroll */
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

  /* ------------------------------------------------------------ stat counters: terminal decode */
  function animateCount(el) {
    const final = (el.dataset.count || "0") + (el.dataset.suffix || "");
    if (REDUCED) { el.textContent = final; return; }
    const dur = 1000;
    const start = performance.now();
    function tick(now) {
      const t = Math.min((now - start) / dur, 1);
      let out = "";
      for (let i = 0; i < final.length; i++) {
        const resolveAt = ((i + 1) / final.length) * 0.8;
        out += t >= resolveAt ? final[i] : String(Math.floor(Math.random() * 10));
      }
      el.textContent = out;
      if (t < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
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

  /* ------------------------------------------------------------ nav: shrink, burger, active link */
  const nav = document.getElementById("siteNav");
  const navLinks = document.getElementById("navLinks");
  const burger = document.getElementById("navBurger");

  window.addEventListener("scroll", () => {
    if (nav) nav.classList.toggle("scrolled", window.scrollY > 40);
  }, { passive: true });

  if (burger && navLinks) {
    burger.addEventListener("click", () => {
      const open = navLinks.classList.toggle("open");
      burger.setAttribute("aria-expanded", String(open));
      burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
      document.body.classList.toggle("menu-open", open);
    });
    navLinks.querySelectorAll("a").forEach((a) =>
      a.addEventListener("click", () => {
        navLinks.classList.remove("open");
        burger.setAttribute("aria-expanded", "false");
        document.body.classList.remove("menu-open");
      }),
    );
  }

  // active section highlight
  const sectionIds = ["story", "market", "own", "rewards", "proof", "faq"];
  const linkFor = {};
  if (navLinks) {
    navLinks.querySelectorAll("a[href^='#']").forEach((a) => {
      linkFor[a.getAttribute("href").slice(1)] = a;
    });
    const secObserver = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          const link = linkFor[e.target.id];
          if (!link) continue;
          if (e.isIntersecting) {
            Object.values(linkFor).forEach((l) => l.classList.remove("active"));
            link.classList.add("active");
          }
        }
      },
      { rootMargin: "-35% 0px -55% 0px" },
    );
    sectionIds.forEach((id) => {
      const el = document.getElementById(id);
      if (el) secObserver.observe(el);
    });
  }

  /* ------------------------------------------------------------ cursor flashlight on the blueprint grid */
  if (FINE_POINTER && !REDUCED) {
    let fx = 0, fy = 0, fRaf = 0;
    window.addEventListener("pointermove", (e) => {
      fx = e.clientX; fy = e.clientY;
      if (!fRaf) {
        fRaf = requestAnimationFrame(() => {
          fRaf = 0;
          document.documentElement.style.setProperty("--mx", fx + "px");
          document.documentElement.style.setProperty("--my", fy + "px");
        });
      }
    }, { passive: true });
  }

  /* ------------------------------------------------------------ the money loop (metro line) */
  const rail = document.getElementById("loopRail");
  const loopFill = document.getElementById("loopFill");
  const loopCoin = document.getElementById("loopCoin");
  const stops = rail ? Array.from(rail.querySelectorAll("[data-stop]")) : [];

  if (rail && loopFill && loopCoin && stops.length) {
    if (REDUCED) {
      loopFill.style.height = "100%";
      loopCoin.style.display = "none";
      stops.forEach((s) => s.classList.add("lit"));
    } else {
      let ticking = false;
      const updateLoop = () => {
        ticking = false;
        const r = rail.getBoundingClientRect();
        const anchor = window.innerHeight * 0.55; // the coin rides this screen line
        const p = clamp((anchor - r.top) / r.height, 0, 1);
        const y = p * r.height;
        loopFill.style.height = y + "px";
        loopCoin.style.top = y + "px";
        for (const s of stops) {
          const sr = s.getBoundingClientRect();
          const nodeY = sr.top - r.top + sr.height / 2;
          s.classList.toggle("lit", y >= nodeY - 10);
        }
      };
      const onScroll = () => {
        if (!ticking) { ticking = true; requestAnimationFrame(updateLoop); }
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      updateLoop();
    }
  }

  /* ------------------------------------------------------------ market simulation
     Payment packets travel buyer -> provider; each arrival logs a receipt.
     AGT-0007 is an AI agent: it buys data and hires robots. */
  const SIM_NODES = {
    A: { x: 280, y: 76, mid: "MID-0001" },
    B: { x: 104, y: 244, mid: "MID-0002" },
    C: { x: 456, y: 244, mid: "MID-0117" },
    D: { x: 280, y: 372, mid: "AGT-0007" },
  };
  const SIM_TRADES = [
    { from: "B", to: "A", svc: "CHARGING", amt: "5.00" },
    { from: "D", to: "C", svc: "MAP_DATA", amt: "0.35" },
    { from: "D", to: "B", svc: "TASK_HIRE", amt: "3.40" },
    { from: "C", to: "A", svc: "CHARGING", amt: "5.00" },
    { from: "B", to: "C", svc: "MAP_DATA", amt: "0.35" },
    { from: "A", to: "C", svc: "INSPECTION", amt: "2.40" },
  ];

  const simSvg = document.getElementById("simSvg");
  const simLog = document.getElementById("simLog");

  function logReceipt(log, from, to, svc, amt, n) {
    const li = document.createElement("li");
    li.innerHTML =
      "RCPT#0" + n + " | " + from + " → " + to +
      " | <b>" + svc + "</b> | <span class='log-amt'>" + amt + " USDG</span> | settled";
    log.prepend(li);
    while (log.children.length > 6) log.removeChild(log.lastChild);
  }

  if (simSvg && simLog && REDUCED) {
    // no animation: still show what the stream looks like
    SIM_TRADES.slice(0, 4).forEach((t, i) =>
      logReceipt(simLog, SIM_NODES[t.from].mid, SIM_NODES[t.to].mid, t.svc, t.amt, 507 + i),
    );
  }

  if (simSvg && simLog && !REDUCED) {
    const pkt = document.getElementById("simPkt");
    const log = simLog;
    let tradeIdx = 0;
    let rcpt = 507;
    let busy = false;

    const nodeEl = (key) => document.getElementById("node" + key);

    function runTrade() {
      if (busy || document.hidden) return;
      busy = true;
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
          // radar ping where the payment landed
          const ping = document.createElementNS("http://www.w3.org/2000/svg", "circle");
          ping.setAttribute("cx", to.x);
          ping.setAttribute("cy", to.y);
          ping.setAttribute("r", 16);
          ping.setAttribute("class", "sim-ping");
          simSvg.appendChild(ping);
          setTimeout(() => ping.remove(), 750);
          logReceipt(log, from.mid, to.mid, t.svc, t.amt, rcpt++);
          busy = false;
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

  /* ------------------------------------------------------------ tilt cards ([data-tilt]) */
  if (FINE_POINTER && !REDUCED) {
    document.querySelectorAll("[data-tilt]").forEach((card) => {
      card.addEventListener("pointermove", (e) => {
        const r = card.getBoundingClientRect();
        const nx = (e.clientX - r.left) / r.width;
        const ny = (e.clientY - r.top) / r.height;
        card.style.transform =
          "perspective(900px) rotateX(" + ((ny - 0.5) * -8).toFixed(2) + "deg)" +
          " rotateY(" + ((nx - 0.5) * 8).toFixed(2) + "deg) translateY(-3px)";
        card.style.setProperty("--sx", (nx * 100).toFixed(1) + "%");
        card.style.setProperty("--sy", (ny * 100).toFixed(1) + "%");
      });
      card.addEventListener("pointerleave", () => {
        card.style.transform = "";
      });
    });
  }

  /* ------------------------------------------------------------ overspend demo (machine accounts) */
  const overspendBtn = document.getElementById("overspendBtn");
  const policyPanel = document.getElementById("policyPanel");
  const deniedLine = document.getElementById("deniedLine");
  const gaugeFill = document.getElementById("gaugeFill");
  const DENY_TEXT = "TX DENIED | DailyCapExceeded | attempted 5.00 | remaining 1.00";
  let denyBusy = false;

  function typeInto(el, text, done) {
    if (REDUCED) { el.textContent = text; if (done) done(); return; }
    el.textContent = "";
    let i = 0;
    const iv = setInterval(() => {
      el.textContent = text.slice(0, ++i);
      if (i >= text.length) { clearInterval(iv); if (done) done(); }
    }, 16);
  }

  function runDenyDemo() {
    if (denyBusy || !policyPanel) return;
    denyBusy = true;
    overspendBtn.disabled = true;
    overspendBtn.textContent = "SUBMITTING…";

    setTimeout(() => {
      if (!REDUCED) policyPanel.classList.add("shake");
      gaugeFill.classList.add("deny");
      deniedLine.classList.add("show");
      overspendBtn.textContent = "DENIED ✕ THE CHAIN SAID NO";
      typeInto(deniedLine, DENY_TEXT, () => {
        setTimeout(() => {
          policyPanel.classList.remove("shake");
          gaugeFill.classList.remove("deny");
          deniedLine.classList.remove("show");
          overspendBtn.disabled = false;
          overspendBtn.textContent = "TRY TO SPEND 5.00 USDG";
          denyBusy = false;
        }, 2400);
      });
    }, REDUCED ? 0 : 420);
  }

  if (overspendBtn && policyPanel && deniedLine && gaugeFill) {
    overspendBtn.addEventListener("click", runDenyDemo);
    // run once by itself so non-clickers still see the point
    const denyObserver = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setTimeout(runDenyDemo, 900);
          denyObserver.disconnect();
        }
      },
      { threshold: 0.5 },
    );
    denyObserver.observe(policyPanel);
  }

  /* ------------------------------------------------------------ ownership slider */
  const ownRange = document.getElementById("ownRange");
  const ownPct = document.getElementById("ownPct");
  const ownPay = document.getElementById("ownPay");
  const ownFill = document.getElementById("ownFill");
  if (ownRange && ownPct && ownPay && ownFill) {
    const MONTHLY = 1000; // USDG, the example month
    const flowTrack = document.getElementById("flowTrack");
    const renderOwn = () => {
      const pct = parseInt(ownRange.value, 10);
      ownPct.textContent = pct;
      ownPay.textContent = Math.round((MONTHLY * pct) / 100);
      ownFill.style.width = pct + "%";
      // the more you own, the faster the money flows to you
      if (flowTrack) flowTrack.parentElement.style.setProperty("--flow-dur", (3.6 - pct * 0.028).toFixed(2) + "s");
    };
    ownRange.addEventListener("input", renderOwn);
    renderOwn();
  }

  /* ------------------------------------------------------------ stock rewards demo */
  const chipsWrap = document.getElementById("stockChips");
  const claimBtn = document.getElementById("claimBtn");
  const claimSym = document.getElementById("claimSym");
  const rwBalance = document.getElementById("rwBalance");
  const rwResult = document.getElementById("rwResult");
  // display-only reference prices, just to size the "≈ shares" line
  const STOCK_PX = { NVDA: 176, TSLA: 250, AMZN: 190, GOOGL: 175, SPY: 560, PLTR: 30, MSFT: 420, AMD: 160 };
  const RW_FULL = 0.0248;

  if (chipsWrap && claimBtn && claimSym && rwBalance && rwResult) {
    let sym = "NVDA";
    let claiming = false;
    let refillIv = 0;

    chipsWrap.querySelectorAll(".stock-chip").forEach((chip) => {
      chip.addEventListener("click", () => {
        sym = chip.dataset.sym;
        chipsWrap.querySelectorAll(".stock-chip").forEach((c) => {
          c.classList.toggle("is-active", c === chip);
          c.setAttribute("aria-pressed", String(c === chip));
        });
        claimSym.textContent = sym;
      });
    });

    claimBtn.addEventListener("click", () => {
      if (claiming) return;
      claiming = true;
      clearInterval(refillIv);
      claimBtn.disabled = true;

      const bal = parseFloat(rwBalance.textContent) || RW_FULL;
      const shares = (bal / STOCK_PX[sym]).toFixed(8);
      const active = chipsWrap.querySelector(".stock-chip.is-active");

      const finish = () => {
        rwBalance.textContent = "0.0000";
        rwResult.textContent = "≈ " + shares + " " + sym + " ✓ CLAIMED ONCHAIN";
        if (active && !REDUCED) {
          active.classList.add("claimed");
          setTimeout(() => active.classList.remove("claimed"), 600);
        }
        // dividends keep accruing: drip the balance back up
        let v = 0;
        refillIv = setInterval(() => {
          v = Math.min(RW_FULL, v + RW_FULL / 40);
          rwBalance.textContent = v.toFixed(4);
          if (v >= RW_FULL) {
            clearInterval(refillIv);
            claimBtn.disabled = false;
            claiming = false;
          }
        }, REDUCED ? 20 : 180);
      };

      if (REDUCED) { finish(); return; }
      // drain the balance into the claim
      const start = performance.now();
      const dur = 650;
      function drain(now) {
        const t = Math.min((now - start) / dur, 1);
        rwBalance.textContent = (bal * (1 - t)).toFixed(4);
        if (t < 1) requestAnimationFrame(drain);
        else finish();
      }
      requestAnimationFrame(drain);
    });

    // dividends never sleep: the balance keeps accruing between claims
    if (!REDUCED) {
      setInterval(() => {
        if (claiming) return;
        const v = parseFloat(rwBalance.textContent);
        if (isNaN(v)) return;
        rwBalance.textContent = (v + 0.0001).toFixed(4);
        rwBalance.classList.add("tick-flash");
        setTimeout(() => rwBalance.classList.remove("tick-flash"), 650);
      }, 3600);
    }
  }

  /* ------------------------------------------------------------ oracle: live price + self-drawing sparkline */
  const oraclePrice = document.getElementById("oraclePrice");
  const oracleSpark = document.getElementById("oracleSpark");
  if (oracleSpark) {
    const N = 32;
    const pts = Array.from({ length: N }, () => 17);
    const draw = () => {
      oracleSpark.setAttribute(
        "points",
        pts.map((y, i) => ((i * 120) / (N - 1)).toFixed(1) + "," + y.toFixed(1)).join(" "),
      );
    };
    if (REDUCED) {
      draw();
    } else {
      let sparkTick = 0;
      setInterval(() => {
        pts.shift();
        pts.push(Math.min(28, Math.max(6, pts[pts.length - 1] + (Math.random() - 0.5) * 7)));
        draw();
        if (oraclePrice && ++sparkTick % 4 === 0) {
          oraclePrice.textContent = "$" + (0.99992 + Math.random() * 0.00006).toFixed(5);
        }
      }, 750);
    }
  }

  /* ------------------------------------------------------------ section tags type themselves out */
  if (!REDUCED) {
    const typeEls = document.querySelectorAll(".section-tag, .eyebrow, .oracle-tag");
    const typeObserver = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue;
          typeObserver.unobserve(e.target);
          const full = e.target.textContent;
          const perChar = Math.min(28, 650 / full.length);
          e.target.textContent = "";
          let i = 0;
          const iv = setInterval(() => {
            e.target.textContent = full.slice(0, ++i);
            if (i >= full.length) clearInterval(iv);
          }, perChar);
        }
      },
      { threshold: 0.6 },
    );
    typeEls.forEach((el) => typeObserver.observe(el));
  }

  /* ------------------------------------------------------------ id card: the machine is working right now */
  const idIncome = document.getElementById("idIncome");
  const idJobs = document.getElementById("idJobs");
  if (idIncome && idJobs && !REDUCED) {
    let income = 6020.0;
    let jobs = 1204;
    let beat = 0;
    const money = (v) =>
      v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " USDG";
    setInterval(() => {
      income += 0.05; // another charge sold
      idIncome.textContent = money(income);
      idIncome.classList.add("tick-flash");
      setTimeout(() => idIncome.classList.remove("tick-flash"), 650);
      if (++beat % 3 === 0) {
        jobs += 1;
        idJobs.textContent = jobs.toLocaleString("en-US");
        idJobs.classList.add("tick-flash");
        setTimeout(() => idJobs.classList.remove("tick-flash"), 650);
      }
    }, 3400);
  }

  /* ------------------------------------------------------------ proof: contract hashes decode on hover */
  if (FINE_POINTER && !REDUCED) {
    const HEXPOOL = "0123456789abcdefABCDEF";
    document.querySelectorAll(".addr-card").forEach((card) => {
      const hash = card.querySelector(".addr-hash");
      if (!hash) return;
      const original = hash.textContent;
      let busy = false;
      card.addEventListener("mouseenter", () => {
        if (busy) return;
        busy = true;
        const start = performance.now();
        const dur = 460;
        function scramble(now) {
          const t = Math.min((now - start) / dur, 1);
          let out = "";
          for (let i = 0; i < original.length; i++) {
            const c = original[i];
            const isHex = HEXPOOL.indexOf(c) !== -1 && i > 1; // keep the 0x
            out += isHex && Math.random() > t
              ? HEXPOOL[Math.floor(Math.random() * HEXPOOL.length)]
              : c;
          }
          hash.textContent = out;
          if (t < 1) requestAnimationFrame(scramble);
          else { hash.textContent = original; busy = false; }
        }
        requestAnimationFrame(scramble);
      });
    });
  }
})();
