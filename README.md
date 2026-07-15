# Servo Protocol

**The financial layer for the machine economy, built on Robinhood Chain.**

Robots are becoming economic actors: they earn for tasks, and they pay for charging, data, maps, compute, and repairs. Servo Protocol is the identity, banking, and commerce infrastructure that makes that possible, with USDG settlement and x402 compatibility from day one.

## The ecosystem

| Layer | Component | Status |
|---|---|---|
| Identity | Machine Registry ("Know Your Machine") | Core contracts complete |
| Banking | Machine Accounts (policy-guarded wallets) | Core contracts complete |
| Commerce | Service Registry (onchain + x402 receipts) | Core contracts complete |
| Treasury | Fleet Vaults (per-machine P&L, revenue splits) | Core contracts complete |
| Gateway | x402-style HTTP 402 paywall (TypeScript) | Reference implementation complete |
| Agent | Machine payment client (402 -> pay -> retry) | Reference implementation complete |
| Risk | Insurance and staking market | Phase 3 |

**Try it:** `cd kit && npm install && npm run demo` boots a local chain, deploys the protocol, and runs a delivery robot that autonomously buys charging sessions over HTTP until its policy envelope blocks overspend, then settles revenue splits to the charging fleet's beneficiaries.

### 1. Machine identity: Know Your Machine

Every machine is issued a **Machine ID (MID)**, an ERC-721 owned by its operator, binding together:

- a unique hardware identity commitment (secure-element key hash),
- an onchain **machine key**: a session address held by the device itself, proven via EIP-712 signature,
- a lifecycle status with an operator kill switch (active, paused, decommissioned),
- a **service record**: attested jobs, uptime, and revenue written by authorized attestors.

Selling a machine transfers the MID; the machine key is revoked automatically so the new operator must re-bind hardware they control.

### 2. Machine banking

Each machine gets a **Machine Account**: funds belong to the operator, but the machine's bound key can spend autonomously inside a policy envelope: per-token daily caps, an optional counterparty allowlist, an account-level pause, plus the registry-level kill switch. The operator retains an unrestricted escape hatch.

### 3. Machine commerce

The **Service Registry** is the discovery and settlement layer for machine-to-machine trade: charging bays, map data, compute bursts, sensor feeds, task handoffs. Settlement is dual-rail:

- **Onchain**: a machine account purchases directly; payment routes to the provider (minus a capped protocol fee) and emits a canonical `ServiceReceipt`.
- **x402**: HTTP 402 gateways settle offchain-style and mirror receipts onchain via authorized facilitators, so every trade builds the same commerce history.

### 4. Fleet treasuries

**Fleet Vaults** hold USDG revenue with per-machine attribution: the verifiable "robot P&L." Distributions flow to beneficiaries (operator, financiers, crew) by fixed basis-point splits with pull-based claims. This earnings history is the dataset that fleet financing and insurance underwriting price against in later phases.

## Repository layout

```
servo-protocol/
  contracts/        Foundry project: core protocol
    src/
      MachineRegistry.sol        identity, keys, attestation
      MachineAccount.sol         policy-guarded machine wallet
      MachineAccountFactory.sol  canonical account per MID
      ServiceRegistry.sol        commerce discovery + receipts, vault settlement
      FleetVault.sol             fleet treasury + robot P&L
    test/           30 tests incl. end-to-end economy flows
    script/         Robinhood Chain / Robinhood Chain Sepolia deployment
  kit/              TypeScript reference stack
    src/
      gateway.ts    x402-style HTTP 402 paywall with onchain receipt verification
      agent.ts      machine payment client (402 -> purchase -> retry with proof)
      contracts.ts  artifact loader + EIP-712 key binding helper
      demo/run.ts   one-command end-to-end machine economy demo
  docs/             architecture and roadmap
```

## Development

```bash
git clone --recurse-submodules https://github.com/servoprotocol-ctrl/servo-protocol.git
cd servo-protocol/contracts
forge build
forge test
```

Deploy to Robinhood Chain Sepolia:

```bash
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --account <keystore>
```

## Why Robinhood Chain

- **Onchain finance, natively**: Robinhood Chain (an Arbitrum-based Ethereum L2) is purpose-built for onchain markets, tokenized assets, and 24/7 settlement, the right home for a machine economy that pays and gets paid.
- **USDG settlement**: machine commerce needs a stable unit of account; USDG is the chain's canonical stablecoin.
- **EVM-standard**: the same Solidity contracts and tooling run unchanged, so identity, accounts, and receipts port directly.
- **The gap**: robotics-crypto lives on Solana and bespoke L1s today; Robinhood Chain has no flagship machine-economy protocol.
