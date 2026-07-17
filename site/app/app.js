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
const OFFERING_FACTORY = "0x371877b3310aEd85a6c85d0f846F13Fb9bcC9Df7";
const USDG = "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168";
const SCAN = "https://robinhoodchain.blockscout.com";

// Stock rewards: earn tokenized stock for using the marketplace. Set STOCK_REWARDS to
// the deployed pool address to switch the panel live; null shows the pre-launch state.
const STOCK_REWARDS = null; // e.g. "0x..."
const NVDA = "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC"; // NVIDIA · Robinhood stock token
const V4_QUOTER = "0x8DC178EFb8111bb0973dD9D722EBEFF267C98F94"; // Uniswap v4 quoter
const NVDA_POOL = { fee: 3000, tickSpacing: 60, hooks: "0x0000000000000000000000000000000000000000" };
const SLIPPAGE_BPS = 100n; // 1% claim slippage bound

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

const offeringFactoryAbi = parseAbi([
  "function offerings() view returns (address[])",
  "function createOffering(address share, uint256 price) returns (address)",
  "event OfferingCreated(address indexed offering, address indexed share, address indexed operator, uint256 price)",
]);
const offeringAbi = parseAbi([
  "function SHARE() view returns (address)",
  "function PRICE() view returns (uint256)",
  "function available() view returns (uint256)",
  "function totalRaised() view returns (uint256)",
  "function sharesSold() view returns (uint256)",
  "function closed() view returns (bool)",
  "function buy(uint256 wholeShares)",
  "function fund(uint256 wholeShares)",
]);
const erc20Abi = parseAbi([
  "function approve(address,uint256) returns (bool)",
  "function allowance(address,address) view returns (uint256)",
]);

const rewardsAbi = parseAbi([
  "function claimable(address) view returns (uint256)",
  "function totalEarned() view returns (uint256)",
  "function totalClaimed() view returns (uint256)",
  "function claimAsStock(address stock, uint256 minOut) returns (uint256)",
  "function claimAsUsdg() returns (uint256)",
]);
const quoterAbi = parseAbi([
  "struct PoolKey { address currency0; address currency1; uint24 fee; int24 tickSpacing; address hooks; }",
  "struct QuoteExactSingleParams { PoolKey poolKey; bool zeroForOne; uint128 exactAmount; bytes hookData; }",
  "function quoteExactInputSingle(QuoteExactSingleParams params) returns (uint256 amountOut, uint256 gasEstimate)",
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
    $("sellBtn").disabled = false;
    setStatus("Connected on Robinhood Chain: " + short(addr), "ok");
    await loadHoldings();
    await loadRewards();
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

// ------------------------------------------------------------ invest (buy)
async function loadOfferings() {
  const box = $("offerings");
  box.innerHTML = '<div class="empty">Reading open offerings…</div>';
  try {
    const offs = await pub.readContract({ address: OFFERING_FACTORY, abi: offeringFactoryAbi, functionName: "offerings" });
    const items = [];
    for (const o of offs) {
      const [share, price, avail, raised, sold, closed] = await Promise.all([
        pub.readContract({ address: o, abi: offeringAbi, functionName: "SHARE" }),
        pub.readContract({ address: o, abi: offeringAbi, functionName: "PRICE" }),
        pub.readContract({ address: o, abi: offeringAbi, functionName: "available" }),
        pub.readContract({ address: o, abi: offeringAbi, functionName: "totalRaised" }),
        pub.readContract({ address: o, abi: offeringAbi, functionName: "sharesSold" }),
        pub.readContract({ address: o, abi: offeringAbi, functionName: "closed" }),
      ]);
      if (closed || avail === 0n) continue;
      const [name, symbol] = await Promise.all([
        pub.readContract({ address: share, abi: shareAbi, functionName: "name" }),
        pub.readContract({ address: share, abi: shareAbi, functionName: "symbol" }),
      ]);
      items.push({ o, price, avail, raised, sold, name, symbol });
    }
    box.innerHTML = items.length ? items.map(offeringCard).join("") : '<div class="empty">No open offerings right now.</div>';
    for (const it of items) {
      const b = document.getElementById("buy-" + it.o);
      if (b) b.addEventListener("click", () => buyShares(it.o, it.price));
    }
  } catch (e) {
    box.innerHTML = '<div class="empty">Failed to read offerings: ' + (e?.shortMessage || e?.message || e) + "</div>";
  }
}

function offeringCard(it) {
  return `<div class="holding">
    <div class="holding-top"><span class="holding-name">${it.name}</span><span class="badge">${it.symbol}</span></div>
    <div class="holding-rows">
      <div><span>PRICE</span><span class="holding-claim">${usdg(it.price)} USDG / share</span></div>
      <div><span>AVAILABLE</span><span>${it.avail.toString()} shares</span></div>
      <div><span>RAISED</span><span>${usdg(it.raised)} USDG</span></div>
    </div>
    <div class="holding-actions">
      <input class="field" style="width:120px;padding:8px 10px" id="qty-${it.o}" placeholder="# shares" />
      <button class="btn btn-sm" id="buy-${it.o}">Buy</button>
      <a class="link" href="${SCAN}/address/${it.o}" target="_blank" rel="noreferrer" style="font-family:var(--font-mono);font-size:11px">view &rarr;</a>
    </div>
  </div>`;
}

async function buyShares(offeringAddr, price) {
  if (!account) { setStatus("Connect your wallet to buy.", "err"); return; }
  const qtyStr = ($("qty-" + offeringAddr).value || "").trim();
  const qty = BigInt(qtyStr || "0");
  if (qty <= 0n) { setStatus("Enter how many shares to buy.", "err"); return; }
  const cost = qty * price;
  try {
    const allowance = await pub.readContract({ address: USDG, abi: erc20Abi, functionName: "allowance", args: [account, offeringAddr] });
    if (allowance < cost) {
      setStatus("Approve USDG in your wallet…");
      const ah = await wallet.writeContract({ address: USDG, abi: erc20Abi, functionName: "approve", args: [offeringAddr, cost] });
      await pub.waitForTransactionReceipt({ hash: ah });
    }
    setStatus("Confirm the purchase in your wallet…");
    const h = await wallet.writeContract({ address: offeringAddr, abi: offeringAbi, functionName: "buy", args: [qty] });
    await pub.waitForTransactionReceipt({ hash: h });
    setStatus("Bought " + qty + " shares. You now own a piece of the asset and earn its income.", "ok");
    await loadOfferings();
    await loadHoldings();
  } catch (e) {
    setStatus("Buy failed: " + (e?.shortMessage || e?.message || e), "err");
  }
}

// ------------------------------------------------------------ sell (create offering + fund)
async function sellShares() {
  if (!account) { setStatus("Connect your wallet to list shares.", "err"); return; }
  const shareAddr = $("sShare").value.trim();
  const priceStr = $("sPrice").value.trim();
  const qtyStr = $("sQty").value.trim();
  if (!/^0x[0-9a-fA-F]{40}$/.test(shareAddr) || !priceStr || !qtyStr) {
    setStatus("Enter the share address, price per share, and how many to sell.", "err"); return;
  }
  const price = parseUnits(priceStr, 6); // USDG per share
  const qty = BigInt(qtyStr);
  try {
    $("sellBtn").disabled = true;
    setStatus("Creating the offering…");
    const ch = await wallet.writeContract({ address: OFFERING_FACTORY, abi: offeringFactoryAbi, functionName: "createOffering", args: [shareAddr, price] });
    const rcpt = await pub.waitForTransactionReceipt({ hash: ch });
    let offering;
    for (const log of rcpt.logs) {
      try { const d = decodeEventLog({ abi: offeringFactoryAbi, data: log.data, topics: log.topics }); if (d.eventName === "OfferingCreated") { offering = d.args.offering; break; } } catch {}
    }
    if (!offering) { const all = await pub.readContract({ address: OFFERING_FACTORY, abi: offeringFactoryAbi, functionName: "offerings" }); offering = all[all.length - 1]; }

    setStatus("Approve your shares to the offering…");
    const ah = await wallet.writeContract({ address: shareAddr, abi: erc20Abi, functionName: "approve", args: [offering, qty * (10n ** 18n)] });
    await pub.waitForTransactionReceipt({ hash: ah });

    setStatus("Fund the offering with your shares…");
    const fh = await wallet.writeContract({ address: offering, abi: offeringAbi, functionName: "fund", args: [qty] });
    await pub.waitForTransactionReceipt({ hash: fh });

    setStatus("Listed " + qty + " shares at " + priceStr + " USDG each. It's live in Invest.", "ok");
    await loadOfferings();
  } catch (e) {
    setStatus("Listing failed: " + (e?.shortMessage || e?.message || e), "err");
  } finally {
    $("sellBtn").disabled = false;
  }
}

// ------------------------------------------------------------ stock rewards
const nvda = (v) => Number(formatUnits(v, 18)).toLocaleString(undefined, { maximumFractionDigits: 6 });

async function quoteNvda(usdgIn) {
  const { result } = await pub.simulateContract({
    address: V4_QUOTER, abi: quoterAbi, functionName: "quoteExactInputSingle",
    args: [{
      poolKey: { currency0: USDG, currency1: NVDA, fee: NVDA_POOL.fee, tickSpacing: NVDA_POOL.tickSpacing, hooks: NVDA_POOL.hooks },
      zeroForOne: true, exactAmount: usdgIn, hookData: "0x",
    }],
  });
  return result[0];
}

async function loadRewards() {
  if (!STOCK_REWARDS) {
    $("rwClaimable").textContent = "0 USDG";
    $("rwQuote").textContent = "—";
    $("rwLifetime").textContent = "—";
    return;
  }
  try {
    const [earned] = await Promise.all([
      pub.readContract({ address: STOCK_REWARDS, abi: rewardsAbi, functionName: "totalEarned" }),
    ]);
    $("rwLifetime").textContent = usdg(earned) + " USDG";
    if (!account) { $("rwHint").textContent = "Connect your wallet to see your dividends."; return; }

    const claimable = await pub.readContract({ address: STOCK_REWARDS, abi: rewardsAbi, functionName: "claimable", args: [account] });
    $("rwClaimable").textContent = usdg(claimable) + " USDG";
    if (claimable > 0n) {
      const out = await quoteNvda(claimable);
      $("rwQuote").textContent = "≈ " + nvda(out) + " NVDA";
      window._rwQuote = out;
      $("claimStockBtn").disabled = false;
      $("claimUsdgBtn").disabled = false;
      $("rwHint").textContent = "Dividends earned from your marketplace activity.";
    } else {
      $("rwQuote").textContent = "—";
      $("claimStockBtn").disabled = true;
      $("claimUsdgBtn").disabled = true;
      $("rwHint").textContent = "Trade on the marketplace to earn stock dividends.";
    }
  } catch (e) {
    $("rwHint").textContent = "Failed to read rewards: " + (e?.shortMessage || e?.message || e);
  }
}

async function claimRewardsAsStock() {
  try {
    $("claimStockBtn").disabled = true;
    const minOut = ((window._rwQuote || 0n) * (10000n - SLIPPAGE_BPS)) / 10000n;
    setStatus("Confirm the claim in your wallet…");
    const hash = await wallet.writeContract({ address: STOCK_REWARDS, abi: rewardsAbi, functionName: "claimAsStock", args: [NVDA, minOut] });
    await pub.waitForTransactionReceipt({ hash });
    setStatus("Dividends claimed as NVDA. Real stock, earned by using the network.", "ok");
    await loadRewards();
  } catch (e) {
    setStatus("Claim failed: " + (e?.shortMessage || e?.message || e), "err");
    $("claimStockBtn").disabled = false;
  }
}

async function claimRewardsAsUsdg() {
  try {
    $("claimUsdgBtn").disabled = true;
    setStatus("Confirm the claim in your wallet…");
    const hash = await wallet.writeContract({ address: STOCK_REWARDS, abi: rewardsAbi, functionName: "claimAsUsdg" });
    await pub.waitForTransactionReceipt({ hash });
    setStatus("Dividends claimed as USDG.", "ok");
    await loadRewards();
  } catch (e) {
    setStatus("Claim failed: " + (e?.shortMessage || e?.message || e), "err");
    $("claimUsdgBtn").disabled = false;
  }
}

// ------------------------------------------------------------ wire up
$("connectBtn").addEventListener("click", connect);
$("claimStockBtn").addEventListener("click", claimRewardsAsStock);
$("claimUsdgBtn").addEventListener("click", claimRewardsAsUsdg);
loadRewards();
$("createBtn").addEventListener("click", createRevenueShare);
$("mintBtn").addEventListener("click", mintShares);
$("sellBtn").addEventListener("click", sellShares);
loadOfferings();
if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => location.reload());
  window.ethereum.on?.("chainChanged", () => location.reload());
}
