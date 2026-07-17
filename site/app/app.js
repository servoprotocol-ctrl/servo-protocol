// SERVO APP — tokenize an asset's income and claim revenue, on Robinhood Chain.
import {
  createPublicClient,
  createWalletClient,
  custom,
  http,
  parseAbi,
  formatUnits,
  parseUnits,
  decodeEventLog,
} from "https://esm.sh/viem@2.21.0";

const RPC = "https://rpc.mainnet.chain.robinhood.com";
const CHAIN_ID = 4663;
const CHAIN_HEX = "0x1237"; // 4663
const FACTORY = "0x4ea7aDfE7501E0a925F89545650A28E7c0797E97";
const SCAN = "https://robinhoodchain.blockscout.com";

const chain = {
  id: CHAIN_ID,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
  blockExplorers: { default: { name: "Blockscout", url: SCAN } },
};

const pub = createPublicClient({ chain, transport: http(RPC) });

const factoryAbi = parseAbi([
  "function shares() view returns (address[])",
  "function createRevenueShare(string name, string symbol, string assetURI) returns (address)",
  "event RevenueShareCreated(address indexed share, address indexed operator, string name, string symbol)",
]);
const shareAbi = parseAbi([
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
  "function totalRevenueDistributed() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function withdrawableRevenueOf(address) view returns (uint256)",
  "function mintShares(address to, uint256 amount)",
  "function claim()",
]);

const $ = (id) => document.getElementById(id);
const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const usdg = (v) => Number(formatUnits(v, 6)).toLocaleString(undefined, { maximumFractionDigits: 6 });
const setStatus = (msg, cls = "") => { const s = $("status"); s.textContent = msg; s.className = "status " + cls; };

let wallet, account;

// ------------------------------------------------------------ connect
async function connect() {
  if (!window.ethereum) {
    setStatus("No wallet found. Install a browser wallet (e.g. MetaMask) to continue.", "err");
    return;
  }
  try {
    const [addr] = await window.ethereum.request({ method: "eth_requestAccounts" });
    account = addr;
    await ensureChain();
    wallet = createWalletClient({ account, chain, transport: custom(window.ethereum) });
    $("connectBtn").textContent = short(addr);
    $("createBtn").disabled = false;
    setStatus("Connected on Robinhood Chain: " + short(addr), "ok");
    await loadHoldings();
  } catch (e) {
    setStatus("Connect failed: " + (e?.shortMessage || e?.message || e), "err");
  }
}

async function ensureChain() {
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CHAIN_HEX }] });
  } catch (e) {
    if (e.code === 4902 || (e.data && e.data.originalError && e.data.originalError.code === 4902)) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: CHAIN_HEX,
          chainName: "Robinhood Chain",
          nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
          rpcUrls: [RPC],
          blockExplorerUrls: [SCAN],
        }],
      });
    } else {
      throw e;
    }
  }
}

// ------------------------------------------------------------ tokenize
async function createRevenueShare() {
  const name = $("tName").value.trim();
  const symbol = $("tSymbol").value.trim();
  const uri = $("tUri").value.trim();
  if (!name || !symbol) { setStatus("Name and symbol are required.", "err"); return; }

  try {
    $("createBtn").disabled = true;
    setStatus("Confirm the transaction in your wallet…");
    const hash = await wallet.writeContract({
      address: FACTORY, abi: factoryAbi, functionName: "createRevenueShare", args: [name, symbol, uri],
    });
    setStatus("Deploying revenue share… " + short(hash));
    const receipt = await pub.waitForTransactionReceipt({ hash });

    // find the created address from the RevenueShareCreated event
    let created;
    for (const log of receipt.logs) {
      try {
        const d = decodeEventLog({ abi: factoryAbi, data: log.data, topics: log.topics });
        if (d.eventName === "RevenueShareCreated") { created = d.args.share; break; }
      } catch { /* not our event */ }
    }
    if (!created) {
      const all = await pub.readContract({ address: FACTORY, abi: factoryAbi, functionName: "shares" });
      created = all[all.length - 1];
    }
    window._created = created;
    $("createdLink").textContent = symbol + " (" + short(created) + ")";
    $("createdLink").href = SCAN + "/address/" + created;
    $("mintBox").classList.remove("hidden");
    setStatus("Revenue share created. Now issue shares to owners.", "ok");
  } catch (e) {
    setStatus("Create failed: " + (e?.shortMessage || e?.message || e), "err");
  } finally {
    $("createBtn").disabled = false;
  }
}

async function mintShares() {
  const to = $("mTo").value.trim();
  const amount = $("mAmount").value.trim();
  if (!window._created) { setStatus("Create a revenue share first.", "err"); return; }
  if (!/^0x[0-9a-fA-F]{40}$/.test(to) || !amount) { setStatus("Enter a valid owner address and share amount.", "err"); return; }
  try {
    $("mintBtn").disabled = true;
    setStatus("Confirm the mint in your wallet…");
    const hash = await wallet.writeContract({
      address: window._created, abi: shareAbi, functionName: "mintShares",
      args: [to, parseUnits(amount, 18)],
    });
    await pub.waitForTransactionReceipt({ hash });
    setStatus("Issued " + amount + " shares to " + short(to) + ".", "ok");
    await loadHoldings();
  } catch (e) {
    setStatus("Mint failed: " + (e?.shortMessage || e?.message || e), "err");
  } finally {
    $("mintBtn").disabled = false;
  }
}

// ------------------------------------------------------------ claim
async function loadHoldings() {
  if (!account) return;
  const box = $("holdings");
  box.innerHTML = '<div class="empty">Reading your revenue shares…</div>';
  try {
    const shares = await pub.readContract({ address: FACTORY, abi: factoryAbi, functionName: "shares" });
    const held = [];
    for (const addr of shares) {
      const [bal, claimable, name, symbol] = await Promise.all([
        pub.readContract({ address: addr, abi: shareAbi, functionName: "balanceOf", args: [account] }),
        pub.readContract({ address: addr, abi: shareAbi, functionName: "withdrawableRevenueOf", args: [account] }),
        pub.readContract({ address: addr, abi: shareAbi, functionName: "name" }),
        pub.readContract({ address: addr, abi: shareAbi, functionName: "symbol" }),
      ]);
      if (bal > 0n || claimable > 0n) held.push({ addr, bal, claimable, name, symbol });
    }
    box.innerHTML = held.length
      ? held.map(holdingRow).join("")
      : '<div class="empty">You don\'t hold any revenue shares yet.</div>';
    for (const h of held) {
      const btn = document.getElementById("claim-" + h.addr);
      if (btn) btn.addEventListener("click", () => claim(h.addr));
    }
  } catch (e) {
    box.innerHTML = '<div class="empty">Failed to read holdings: ' + (e?.shortMessage || e?.message || e) + "</div>";
  }
}

function holdingRow(h) {
  const shares = Math.round(Number(formatUnits(h.bal, 18))).toLocaleString();
  const canClaim = h.claimable > 0n;
  return `<div class="holding">
    <div class="holding-top"><span class="holding-name">${h.name}</span><span class="badge">${h.symbol}</span></div>
    <div class="holding-rows">
      <div><span>YOUR SHARES</span><span>${shares}</span></div>
      <div><span>CLAIMABLE</span><span class="holding-claim">${usdg(h.claimable)} USDG</span></div>
    </div>
    <div class="holding-actions">
      <button class="btn btn-sm" id="claim-${h.addr}" ${canClaim ? "" : "disabled"}>Claim</button>
      <a class="link" href="${SCAN}/address/${h.addr}" target="_blank" rel="noreferrer" style="font-family:var(--font-mono);font-size:11px">view onchain &rarr;</a>
    </div>
  </div>`;
}

async function claim(addr) {
  try {
    setStatus("Confirm the claim in your wallet…");
    const hash = await wallet.writeContract({ address: addr, abi: shareAbi, functionName: "claim" });
    await pub.waitForTransactionReceipt({ hash });
    setStatus("Revenue claimed. USDG is in your wallet.", "ok");
    await loadHoldings();
  } catch (e) {
    setStatus("Claim failed: " + (e?.shortMessage || e?.message || e), "err");
  }
}

// ------------------------------------------------------------ wire up
$("connectBtn").addEventListener("click", connect);
$("createBtn").addEventListener("click", createRevenueShare);
$("mintBtn").addEventListener("click", mintShares);
if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => location.reload());
  window.ethereum.on?.("chainChanged", () => location.reload());
}
