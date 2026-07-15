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
