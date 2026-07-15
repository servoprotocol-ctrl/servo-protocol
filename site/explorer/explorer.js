// SERVO REGISTRY EXPLORER — reads the live protocol state from Robinhood Chain.
import {
  createPublicClient,
  http,
  parseAbi,
  formatUnits,
  keccak256,
  toBytes,
} from "https://esm.sh/viem@2.21.0";

// ---------------------------------------------------------------- config
// Robinhood Chain (id 4663).
const RPC = "https://rpc.mainnet.chain.robinhood.com";
const REGISTRY = "0x7896Dba19A72278d66C9f0640262C511D24CB871";
const SERVICES = "0x24f2f3536F65CA2AE36136E3B217a390251a1a90";
const DEPLOY_BLOCK = 10126181n;
const SCAN = "https://robinhoodchain.blockscout.com/address/";

document.getElementById("scanReg").href = SERVICES ? SCAN + SERVICES : "https://robinhoodchain.blockscout.com";

// JSON-RPC batching with retry/backoff. (Multicall batching is enabled once
// Multicall3 is confirmed on Robinhood Chain.)
const client = createPublicClient({
  transport: http(RPC, { batch: true, retryCount: 4, retryDelay: 700 }),
});

const registryAbi = parseAbi([
  "struct Machine { uint8 status; uint8 class_; address machineKey; bytes32 hardwareHash; uint64 registeredAt; uint64 jobsAttested; uint128 revenueAttested; string metadataURI; }",
  "function nextMid() view returns (uint256)",
  "function ownerOf(uint256) view returns (address)",
  "function getMachine(uint256) view returns (Machine)",
]);

const servicesAbi = parseAbi([
  "struct Service { address provider; address payTo; address token; uint96 price; uint256 providerMid; bool active; bool vaultSettlement; bytes32 category; uint64 unitsSold; uint128 grossRevenue; string uri; }",
  "function nextServiceId() view returns (uint256)",
  "function getService(uint256) view returns (Service)",
  "function protocolFeeBps() view returns (uint16)",
  "event ServiceReceipt(uint256 indexed serviceId, uint256 indexed buyerMid, uint256 indexed providerMid, address token, uint256 amount, uint256 fee, bool external_)",
]);

// ---------------------------------------------------------------- lookups
const CLASSES = ["UNSPECIFIED", "HUMANOID", "MOBILE_GROUND", "AERIAL", "MANIPULATOR", "VEHICLE", "STATIONARY", "VIRTUAL"];
const STATUS = ["NONE", "ACTIVE", "PAUSED", "DECOMMISSIONED"];
const STATUS_CLASS = ["", "b-active", "b-paused", "b-decom"];

// map known category hashes -> label
const KNOWN_CATS = ["CHARGING", "MAP_DATA", "COMPUTE", "SENSOR_FEED", "TASK_HANDOFF", "DOCKING", "TOLL", "INSPECTION"];
const CAT_MAP = {};
for (const c of KNOWN_CATS) CAT_MAP[keccak256(toBytes(c))] = c;

// ---------------------------------------------------------------- helpers
const $ = (id) => document.getElementById(id);
const short = (a) => (a && a !== "0x0000000000000000000000000000000000000000" ? a.slice(0, 6) + "…" + a.slice(-4) : "—");
const mid = (n) => "MID-" + String(n).padStart(4, "0");
const usdc = (v) => Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 2 });
const cat = (h) => CAT_MAP[h] || "SERVICE";
const scanLink = (addr, label) => `<a href="${SCAN}${addr}" target="_blank" rel="noreferrer">${label}</a>`;

function ago(ts) {
  const s = Math.floor(Date.now() / 1000) - Number(ts);
  if (s < 60) return s + "s ago";
  if (s < 3600) return Math.floor(s / 60) + "m ago";
  if (s < 86400) return Math.floor(s / 3600) + "h ago";
  return Math.floor(s / 86400) + "d ago";
}

// ---------------------------------------------------------------- render
function machineCard(id, m, owner) {
  const st = Number(m.status);
  return `<div class="card">
    <div class="card-head"><span class="card-id">${mid(id)}</span>
      <span class="badge ${STATUS_CLASS[st]}">${STATUS[st]}</span></div>
    <div class="card-sub">${CLASSES[Number(m.class_)]}</div>
    <div class="card-rows">
      <div><span>OPERATOR</span><span>${scanLink(owner, short(owner))}</span></div>
      <div><span>SESSION KEY</span><span>${m.machineKey && m.machineKey !== "0x0000000000000000000000000000000000000000" ? '<span class="accent">BOUND ✓</span>' : "—"}</span></div>
      <div><span>JOBS</span><span>${m.jobsAttested}</span></div>
      <div><span>REVENUE</span><span>${usdc(m.revenueAttested)} USDG</span></div>
      <div><span>REGISTERED</span><span>${ago(m.registeredAt)}</span></div>
    </div>
  </div>`;
}

function serviceCard(id, s) {
  return `<div class="card">
    <div class="card-head"><span class="card-cat">${cat(s.category)}</span>
      <span class="badge ${s.active ? "b-active" : "b-paused"}">${s.active ? "ACTIVE" : "INACTIVE"}</span></div>
    <div class="card-id" style="font-size:22px;margin-bottom:14px">${usdc(s.price)} <span style="font-size:11px;color:var(--ink-faint)">USDG</span></div>
    <div class="card-rows">
      <div><span>SERVICE</span><span>SVC-${String(id).padStart(3, "0")}</span></div>
      <div><span>PROVIDER</span><span>${s.providerMid > 0n ? mid(s.providerMid) : "—"}</span></div>
      <div><span>UNITS SOLD</span><span>${s.unitsSold}</span></div>
      <div><span>GROSS</span><span>${usdc(s.grossRevenue)} USDG</span></div>
      <div><span>SETTLEMENT</span><span>${s.vaultSettlement ? "VAULT" : "DIRECT"}</span></div>
    </div>
  </div>`;
}

function receiptRow(r) {
  const a = r.args;
  return `<tr>
    <td>${scanLink(r.transactionHash, "RCPT " + r.transactionHash.slice(0, 8))}</td>
    <td>${a.buyerMid > 0n ? mid(a.buyerMid) : "external"}</td>
    <td>${a.providerMid > 0n ? mid(a.providerMid) : "—"}</td>
    <td class="amt">${usdc(a.amount)} USDG</td>
    <td>${usdc(a.fee)} USDG</td>
    <td>${a.external_ ? '<span class="ext">x402</span>' : "onchain"}</td>
  </tr>`;
}

// receipts fetched in <=10k block windows (public RPC limit)
async function fetchReceipts() {
  const latest = await client.getBlockNumber();
  const CHUNK = 9000n;
  const all = [];
  let from = DEPLOY_BLOCK;
  let guard = 0;
  while (from <= latest && guard < 60) {
    const to = from + CHUNK > latest ? latest : from + CHUNK;
    const logs = await client.getContractEvents({
      address: SERVICES,
      abi: servicesAbi,
      eventName: "ServiceReceipt",
      fromBlock: from,
      toBlock: to,
    });
    all.push(...logs);
    from = to + 1n;
    guard++;
  }
  return all;
}

// ---------------------------------------------------------------- load
async function load() {
  const btn = $("refreshBtn");
  // Pre-deployment: no contracts on Robinhood Chain yet — show a deploying state.
  if (!REGISTRY || !SERVICES) {
    $("updated").textContent = "deploying to Robinhood Chain";
    const msg = '<div class="empty">Deploying to Robinhood Chain. Machines, services, and receipts appear here live the moment the core lands onchain.</div>';
    $("machines").innerHTML = msg;
    $("services").innerHTML = msg;
    $("receiptsWrap").innerHTML = msg;
    return;
  }
  btn.disabled = true;
  $("updated").textContent = "reading Robinhood Chain…";
  try {
    const [nextMid, nextSvc] = await Promise.all([
      client.readContract({ address: REGISTRY, abi: registryAbi, functionName: "nextMid" }),
      client.readContract({ address: SERVICES, abi: servicesAbi, functionName: "nextServiceId" }),
    ]);
    const machineCount = Number(nextMid) - 1;
    const serviceCount = Number(nextSvc) - 1;

    // machines
    const midIds = Array.from({ length: machineCount }, (_, i) => BigInt(i + 1));
    const machines = await Promise.all(
      midIds.map(async (id) => {
        const [m, owner] = await Promise.all([
          client.readContract({ address: REGISTRY, abi: registryAbi, functionName: "getMachine", args: [id] }),
          client.readContract({ address: REGISTRY, abi: registryAbi, functionName: "ownerOf", args: [id] }),
        ]);
        return { id, m, owner };
      }),
    );
    $("machines").innerHTML = machines.length
      ? machines.map((x) => machineCard(x.id, x.m, x.owner)).join("")
      : '<div class="empty">No machines registered yet.</div>';
    $("cMachines").textContent = machineCount;
    $("statMachines").textContent = machineCount;

    // services
    const svcIds = Array.from({ length: serviceCount }, (_, i) => BigInt(i + 1));
    const services = await Promise.all(
      svcIds.map(async (id) => ({
        id,
        s: await client.readContract({ address: SERVICES, abi: servicesAbi, functionName: "getService", args: [id] }),
      })),
    );
    $("services").innerHTML = services.length
      ? services.map((x) => serviceCard(x.id, x.s)).join("")
      : '<div class="empty">No services listed yet.</div>';
    $("cServices").textContent = serviceCount;
    $("statServices").textContent = serviceCount;

    // receipts — public RPC caps eth_getLogs at a 10k block range, so chunk it.
    const logs = await fetchReceipts();
    logs.reverse(); // newest first
    const volume = logs.reduce((acc, l) => acc + l.args.amount, 0n);
    $("cReceipts").textContent = logs.length;
    $("statReceipts").textContent = logs.length;
    $("statVolume").textContent = usdc(volume);
    $("receiptsWrap").innerHTML = logs.length
      ? `<table><thead><tr><th>RECEIPT</th><th>BUYER</th><th>PROVIDER</th><th>AMOUNT</th><th>FEE</th><th>RAIL</th></tr></thead>
         <tbody>${logs.map(receiptRow).join("")}</tbody></table>`
      : '<div class="empty">No receipts yet. The first settlement will appear here live.</div>';

    const now = new Date();
    $("updated").textContent = "updated " + now.toLocaleTimeString();
  } catch (e) {
    $("updated").innerHTML = '<span class="err">read failed: ' + (e?.shortMessage || e?.message || e) + "</span>";
  } finally {
    btn.disabled = false;
  }
}

$("refreshBtn").addEventListener("click", load);
load();
setInterval(load, 60000); // auto-refresh every 60s
