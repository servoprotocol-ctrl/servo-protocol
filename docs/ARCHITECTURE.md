# Servo Protocol Architecture

## Design principles

1. **Identity before money.** Nothing moves value without resolving through the Machine Registry. Every payment, receipt, and revenue attribution is keyed by MID, which is what makes the data financeable later.
2. **Operator sovereignty, machine autonomy.** Machines act autonomously inside operator-defined policy envelopes. The operator always holds a kill switch at two levels (registry status and account pause) and an unrestricted `execute` escape hatch.
3. **Dual-rail settlement.** Onchain purchases and x402 gateway settlements converge on one canonical receipt stream so commerce history is complete regardless of rail.
4. **Pull over push.** Vault distributions accrue and are claimed, never force-pushed, to avoid griefing and reentrancy surface.

## Contract map

```
MachineRegistry (ERC-721, EIP-712)
  |-- identity: hardwareHash (unique), metadataURI, class
  |-- machineKey binding: EIP-712 proof of key possession; revoked on transfer
  |-- lifecycle: Active / Paused / Decommissioned (terminal)
  |-- service record: attestors write JOB_COMPLETED / REVENUE / UPTIME events
  |
  |--> MachineAccountFactory
  |       one canonical MachineAccount per MID, resolvable by anyone
  |
  |--> MachineAccount (per machine)
  |       owner  = current MID owner (operator), resolved live from registry
  |       signer = bound machineKey, policy-constrained:
  |                daily caps per token, counterparty allowlist, pause
  |       paths: pay() free-form, purchase() via ServiceRegistry
  |
  |--> ServiceRegistry
  |       listings: provider, payTo, token, price, category, URI (x402 endpoint)
  |       purchase(): pulls payment, skims capped protocol fee, emits ServiceReceipt
  |       vaultSettlement: routes net revenue through FleetVault.deposit so onchain
  |                        sales are attributed to the providing machine's P&L
  |       recordExternalReceipt(): x402 facilitators mirror offchain settlements
  |
  |--> FleetVault (per fleet)
          membership: operator-enrolled MIDs (must own them in registry)
          deposit(mid, amount): USDG in, attributed to machine
          distribute()/claim(): bps splits, last beneficiary absorbs dust
```

## Key mechanisms

### Machine key binding

The device generates a keypair in its secure element. The operator submits `bindMachineKey(mid, key, sig)` where `sig` is the device's EIP-712 signature over `KeyBinding(mid, operator, machineKey)`. This proves the operator controls hardware that holds the key, without the device ever exposing it. Rebinding revokes the old key; transferring the MID revokes automatically.

### Policy envelope evaluation

Machine-key spending passes four gates, in order:

1. caller is the currently bound machine key,
2. machine is Active in the registry (registry-level kill switch),
3. account is not paused (account-level kill switch),
4. token has a nonzero daily cap, counterparty passes the allowlist if enabled, and the day's spend stays under cap (UTC-day epochs).

### Receipts as the commerce graph

`ServiceReceipt(serviceId, buyerMid, providerMid, token, amount, fee, external)` is the atomic unit of the machine economy. Indexed by both MIDs, it gives every machine a verifiable purchase and sales history, which composes with registry attestations into the underwriting dataset.

### x402 integration (phase 2, reference implementation in kit/)

`kit/src/gateway.ts` implements the paywall: a request without proof gets HTTP 402 with x402-style payment requirements (scheme `servo-onchain`: service id, price, asset, settlement contract). The machine settles via `MachineAccount.purchase` and retries with `x-payment: <txHash>`; the gateway verifies the `ServiceReceipt` log (correct service, successful tx, replay-protected) and serves the resource. `kit/src/agent.ts` is the client half: fetch, parse 402, pay under policy, retry with proof.

For pure-x402 offchain settlements, the gateway holds a facilitator key and mirrors payments with `recordExternalReceipt`. Misbehaving facilitators are removed by governance; longer term this moves to a staked model with slashing.

## Trust assumptions (v1)

- Attestors and facilitators are governance-authorized, trusted writers. Phase 3 replaces this with staked attestation and dispute windows.
- Vault revenue attribution is open (any payer can deposit against an enrolled MID); the constraint is enrollment, which requires registry ownership by the vault operator.
- MachineAccount policy protects against a compromised machine key up to (daily cap x tokens configured). Hardware compromise of the operator key is out of scope, as with any wallet.

## Phase plan

- **Phase 1 (this repo):** identity, accounts, commerce, vaults on Robinhood Chain Sepolia, then Robinhood Chain.
- **Phase 2:** x402 gateway reference implementation (TypeScript), indexer + registry explorer app, fleet dashboard, operator SDK.
- **Phase 3:** staked attestation network, insurance market (uptime and liability underwriting against service records), fleet financing vaults (revenue-share offerings via batch auction).
