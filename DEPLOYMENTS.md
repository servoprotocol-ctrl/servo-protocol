# Deployments

## Target: Robinhood Chain (chain id 4663)

Servo is pivoting to **Robinhood Chain**, an Arbitrum-based Ethereum L2 for onchain
finance. Gas is paid in ETH; settlement is in **USDG** (Global Dollar), the chain's
canonical stablecoin.

### Network
- Chain id: `4663`
- RPC (public): `https://rpc.mainnet.chain.robinhood.com`
- Explorer: `https://robinhoodchain.blockscout.com`
- USDG (settlement): `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`
- WETH: `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`

### Live contracts (verified on Blockscout)

| Contract | Address |
|---|---|
| MachineRegistry | [`0x7896Dba19A72278d66C9f0640262C511D24CB871`](https://robinhoodchain.blockscout.com/address/0x7896Dba19A72278d66C9f0640262C511D24CB871) |
| ServiceRegistry | [`0x24f2f3536F65CA2AE36136E3B217a390251a1a90`](https://robinhoodchain.blockscout.com/address/0x24f2f3536F65CA2AE36136E3B217a390251a1a90) |
| MachineAccountFactory | [`0x6458665705D496b8ec84d4C4e98e1B23f07512B4`](https://robinhoodchain.blockscout.com/address/0x6458665705D496b8ec84d4C4e98e1B23f07512B4) |

- Governance (owner): `0x08F3b58CACDd16Bc6B71cAfC16b7886F3205E27d` (deployer EOA, Option A)
- Treasury (fees): same. Protocol fee 1% (100 bps), hard cap 5%.
- ServiceRegistry authorized as commerce recorder: yes
- USDG confirmed 6 decimals.

### Genesis dogfood (live on Robinhood Chain)
- MID-0001 — charging station (provider)
- MID-0002 — delivery bot (buyer), MachineAccount `0x23FDEfF1545494998bbe3238b6030689f7A1470C`, session key bound, 5 USDG/day cap
- Service #1 — CHARGING, 0.05 USDG/session, provider MID-0001
- Browse it live at `/explorer`

### Remaining
- [ ] Fund the bot account with USDG -> run the first purchases (receipts + P&L)
- [ ] Migrate governance + treasury to a Safe before inviting outside fleets

---

## Prior deployment (Base mainnet, deprecated)

Servo was first deployed and dogfooded on Base mainnet (chain 8453): MachineRegistry
`0x78A6DfC16BD166f86F0263B1Eec3c697372d8ab6`, ServiceRegistry
`0x7896Dba19A72278d66C9f0640262C511D24CB871`, MachineAccountFactory
`0x24f2f3536F65CA2AE36136E3B217a390251a1a90`, verified on BaseScan, with a genesis
dogfood of 2 machines, 1 service, and 3 autonomous receipts. Superseded by the
Robinhood Chain deployment above.

## RWA Revenue Rails (Robinhood Chain)

- RevenueShareFactory (v2, auto-routing): [`0x4ea7aDfE7501E0a925F89545650A28E7c0797E97`](https://robinhoodchain.blockscout.com/address/0x4ea7aDfE7501E0a925F89545650A28E7c0797E97) (verified) — the address the Explorer reads.
- Charger RevenueShare (sCHG): [`0x664b19AC98fEb5051d4aE659eBb4D8B6e326CD0e`](https://robinhoodchain.blockscout.com/address/0x664b19AC98fEb5051d4aE659eBb4D8B6e326CD0e) (verified) — 70/30 split.
  - AUTO-ROUTING LIVE: SVC #1 payTo routes charging revenue here; syncRevenue()/claim() distributes to holders. Proven: bot bought 2 charges -> 0.099 USDG routed -> operator 0.0693 / backer 0.0297.
- Superseded: old factory 0xa1e5fd12... + demo share 0x81138bAe... (pre-auto-routing).

## Primary Issuance (Robinhood Chain)

- RevenueShareOfferingFactory: [`0x371877b3310aEd85a6c85d0f846F13Fb9bcC9Df7`](https://robinhoodchain.blockscout.com/address/0x371877b3310aEd85a6c85d0f846F13Fb9bcC9Df7) (verified)
- Demo offering (charger shares @ 0.5 USDG): [`0x02774eF5d1E68B7eCB4D261a24Cb2822DbeE652E`](https://robinhoodchain.blockscout.com/address/0x02774eF5d1E68B7eCB4D261a24Cb2822DbeE652E) (verified)
  - LIVE: a real buyer paid 5 USDG for 10 shares (10%) of the charger; capital to operator, buyer now earns 10% of its income.
- Wired into the Servo App (/app): Sell shares (create offering + fund), Invest (browse + buy).

## Stock Rewards (Robinhood Chain) — LIVE 2026-07-17

Earn tokenized stock for using the marketplace: half the 1% protocol fee on every
settled trade becomes a buyer dividend, claimable as NVDA via Uniswap v4.

| Contract | Address |
|---|---|
| StockRewards | [`0x56E80cB3eE4ccF34bFC1A9F0d23EC0FC1C8a40c7`](https://robinhoodchain.blockscout.com/address/0x56E80cB3eE4ccF34bFC1A9F0d23EC0FC1C8a40c7) (verified) |
| UniswapV4SwapAdapter | [`0x4F6A5Ac90a6D1E4a27c78c84e948cD13237682bB`](https://robinhoodchain.blockscout.com/address/0x4F6A5Ac90a6D1E4a27c78c84e948cD13237682bB) (verified) |
| ServiceRegistry v2 (rewards-enabled) | [`0x954AC5b2772de8D20069bdC51683E9757CA9F697`](https://robinhoodchain.blockscout.com/address/0x954AC5b2772de8D20069bdC51683E9757CA9F697) (verified) |
| MachineAccountFactory v2 | [`0x4903D8AB91fC9F2d29255c6cfb5F096964110354`](https://robinhoodchain.blockscout.com/address/0x4903D8AB91fC9F2d29255c6cfb5F096964110354) (verified) |
| Bot MachineAccount v2 (MID-0002) | [`0x09c11C2E607d8b273853C2b84F6594ED832F876D`](https://robinhoodchain.blockscout.com/address/0x09c11C2E607d8b273853C2b84F6594ED832F876D) |

- Wiring: v2 is the commerce recorder (v1 recorder revoked, its service delisted and
  re-listed on v2 as service 1, same 0.05 USDG price, payTo = sCHG). Reward split
  50/50 (rewardShareBps 5000). Adapter pinned to the live USDG/NVDA v4 pool
  (fee 3000, tickSpacing 60, hooks 0x0). NVDA = `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC`
  (the BeaconProxy Robinhood stock token). Default claim stock: NVDA.
- PROVEN LIVE: the delivery bot bought 2 charging sessions on v2
  (0x30b70e2b…, 0xe4c2f56d…), accrued 0.0005 USDG of dividends (50% of the fee),
  and claimed them as REAL NVDA via Uniswap v4 (0xa3b2db35…): the robot's account
  now holds 0.0000024333 NVDA. Machines earning stock, onchain.
- v1 ServiceRegistry remains onchain for receipt history; Explorer reads both.

## Chainlink integration (Robinhood Chain)

- ServoOracle: [`0x2A9684A30d0F8C2c3B84BFe354079aad82e3B107`](https://robinhoodchain.blockscout.com/address/0x2A9684A30d0F8C2c3B84BFe354079aad82e3B107) (verified)
  - Reads Chainlink's live USDG/USD feed (`0x8bEeE3503F6860D5dac4cE26b5eEe92982951c2e`) with staleness + bad-price guards.
  - Values Servo's USDG figures in real, Chainlink-verified USD (reflects depeg). Live read confirmed: USDG = $0.99995.
  - Explorer shows the live Chainlink USDG price + USD equivalents. Robinhood Chain is Chainlink-powered.
