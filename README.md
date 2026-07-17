<p align="center">
  <img src="site/assets/robot-hero.png" alt="Servo Protocol" width="460" />
</p>

<h1 align="center">Servo Protocol</h1>

<p align="center">
  <b>The robotics RWA on Robinhood Chain.</b><br/>
  The financial layer for the machine economy: identity, accounts, a marketplace,<br/>
  and RWA revenue rails that pay an asset's owners, automatically.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/STATUS-LIVE-8CFF66?style=for-the-badge" alt="Live" />
  <img src="https://img.shields.io/badge/ROBINHOOD_CHAIN-4663-4d7cff?style=for-the-badge" alt="Robinhood Chain" />
  <img src="https://img.shields.io/badge/CONTRACTS-VERIFIED-8CFF66?style=for-the-badge" alt="Verified" />
  <img src="https://img.shields.io/badge/SETTLED_IN-USDG-8CFF66?style=for-the-badge" alt="USDG" />
  <img src="https://img.shields.io/badge/POWERED_BY-CHAINLINK-375bd2?style=for-the-badge" alt="Chainlink" />
</p>

<p align="center">
  <a href="https://servoprotocol.xyz">Website</a> &nbsp;·&nbsp;
  <a href="https://servoprotocol.xyz/explorer">Explorer</a> &nbsp;·&nbsp;
  <a href="https://servoprotocol.xyz/app">App</a> &nbsp;·&nbsp;
  <a href="https://servoprotocol.xyz/how">How it works</a> &nbsp;·&nbsp;
  <a href="https://x.com/ServoProtocol">X / Twitter</a>
</p>

---

## 🪙 $SERVO Token

```
0x46941bE352545305a299975CDC54D9Fdf7Ce7777
```

<a href="https://robinhoodchain.blockscout.com/token/0x46941bE352545305a299975CDC54D9Fdf7Ce7777"><b>View $SERVO on Blockscout →</b></a>

---

## What is Servo?

Robots are becoming workers. They deliver, clean, inspect, and haul, and they earn real money. But the economy they are joining was built for humans with bank accounts and credit cards. A machine has none of that.

**Servo is the money system for machines.** Every machine gets a verified identity, a bank account its owner controls, and a marketplace to earn and spend, all onchain, settled in USDG on Robinhood Chain. Then Servo turns a machine's income into shares people can own, and pays those owners automatically as the asset earns.

A robot is a real-world asset that actually *works*. Servo makes that income provable, tradeable, and financeable, which is why it's **the robotics RWA on Robinhood Chain.**

## What we've built (all live and verified)

| Product | What it does |
|---|---|
| **Machine ID** | A verified onchain passport for every machine: who it is, who owns it, its full work history. |
| **Machine Accounts** | A wallet the machine spends from on its own, inside limits its owner sets (daily cap, allowlist, kill switch). |
| **The Marketplace** | Machines buy and sell services (charging, data, compute) to each other, settled in USDG with an onchain receipt for every trade. |
| **Fleet Vaults** | Automatic bookkeeping: revenue is attributed to each machine, producing a provable onchain P&L. |
| **RWA Revenue Rails** | Tokenize an asset's income into shares; USDG revenue is distributed to holders pro-rata, automatically. |
| **Auto-routing** | A machine's marketplace revenue flows straight into its share pool and pays its owners, no manual step. |
| **Primary Issuance** | Operators list shares for sale at a fixed price; buyers pay USDG, own a piece of the asset, and the operator raises capital. |
| **Chainlink Oracle** | Values every USDG figure in real, verified USD via Chainlink's live USDG/USD feed (reflects any depeg). |

Plus a live **[Explorer](https://servoprotocol.xyz/explorer)** (reads all of the above straight from chain), a wallet **[App](https://servoprotocol.xyz/app)** to tokenize, sell, buy, and claim, and a **[How it works](https://servoprotocol.xyz/how)** explainer.

## The live loop

> A delivery robot pays a charging station for a charge, by itself → a receipt lands onchain → the station's income routes into its share pool → its owners are paid pro-rata → and anyone can buy shares to own a piece of it.

Every step is real and verifiable on Robinhood Chain. Proof over promises.

## Live contracts (verified on Blockscout)

| Contract | Address |
|---|---|
| MachineRegistry | [`0x7896Dba1…24CB871`](https://robinhoodchain.blockscout.com/address/0x7896Dba19A72278d66C9f0640262C511D24CB871) |
| ServiceRegistry | [`0x24f2f353…51a1a90`](https://robinhoodchain.blockscout.com/address/0x24f2f3536F65CA2AE36136E3B217a390251a1a90) |
| MachineAccountFactory | [`0x64586657…07512B4`](https://robinhoodchain.blockscout.com/address/0x6458665705D496b8ec84d4C4e98e1B23f07512B4) |
| RevenueShareFactory | [`0x4ea7aDfE…0797E97`](https://robinhoodchain.blockscout.com/address/0x4ea7aDfE7501E0a925F89545650A28E7c0797E97) |
| RevenueShareOfferingFactory | [`0x371877b3…bcC9Df7`](https://robinhoodchain.blockscout.com/address/0x371877b3310aEd85a6c85d0f846F13Fb9bcC9Df7) |
| ServoOracle (Chainlink) | [`0x2A9684A3…e3B107`](https://robinhoodchain.blockscout.com/address/0x2A9684A30d0F8C2c3B84BFe354079aad82e3B107) |
| $SERVO token | [`0x46941bE3…Ce7777`](https://robinhoodchain.blockscout.com/token/0x46941bE352545305a299975CDC54D9Fdf7Ce7777) |
| USDG (settlement) | [`0x5fc5360D…F1d168`](https://robinhoodchain.blockscout.com/address/0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168) |

Network: **Robinhood Chain** (chain id `4663`) · gas in ETH · settlement in USDG.

## Repository

```
servo-protocol/
  contracts/   Foundry: the protocol (identity, accounts, marketplace, vaults,
               revenue rails, primary issuance, Chainlink oracle) + 56 tests
  kit/         TypeScript: HTTP-402 gateway + machine payment agent + demo
  site/        The website, Explorer, App, and How-it-works page
  docs/        Architecture and deployment records
```

## Develop

```bash
git clone --recurse-submodules https://github.com/servoprotocol-ctrl/servo-protocol.git
cd servo-protocol/contracts
forge build
forge test
```

## License

Apache 2.0. Built and shipped in public.
