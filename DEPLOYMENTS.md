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

### Status: pending redeploy
The core is built, security-reviewed, and passing 31 tests. To go live it must be
redeployed on Robinhood Chain, which requires the deployer funded with a little ETH
on chain 4663 (plus some USDG to re-run the genesis dogfood).

Deployer: `0x08F3b58CACDd16Bc6B71cAfC16b7886F3205E27d` (keystore `servo-deployer`).
Governance + treasury: deployer EOA for launch (Option A; migrate to a Safe later).

### Redeploy checklist
- [ ] Bridge ETH to the deployer on Robinhood Chain (gas)
- [ ] Confirm USDG decimals via `cast call <USDG> "decimals()(uint8)"` before dogfood
- [ ] `forge script script/Deploy.s.sol --rpc-url robinhood --account servo-deployer --broadcast`
- [ ] Verify all three contracts on Blockscout
- [ ] Wire the new addresses into the site (`index.html` deployed section + roadmap, `explorer/explorer.js`, `ecosystem/index.html`) and re-enable the Explorer
- [ ] Re-run the genesis dogfood in USDG (`script/Dogfood.s.sol`)
- [ ] Migrate governance + treasury to a Safe before inviting outside fleets

---

## Prior deployment (Base mainnet, deprecated)

Servo was first deployed and dogfooded on Base mainnet (chain 8453): MachineRegistry
`0x78A6DfC16BD166f86F0263B1Eec3c697372d8ab6`, ServiceRegistry
`0x7896Dba19A72278d66C9f0640262C511D24CB871`, MachineAccountFactory
`0x24f2f3536F65CA2AE36136E3B217a390251a1a90`, verified on BaseScan, with a genesis
dogfood of 2 machines, 1 service, and 3 autonomous receipts. Superseded by the
Robinhood Chain deployment above.
