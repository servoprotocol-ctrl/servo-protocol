# Deployments

## Base Mainnet (chain id 8453)

Deployed core protocol. Governance and treasury are the deployer EOA (Option A;
transferable to a Safe later). Protocol fee: 1% (100 bps), hard cap 5%.

| Contract | Address |
|---|---|
| MachineRegistry | [`0x78A6DfC16BD166f86F0263B1Eec3c697372d8ab6`](https://basescan.org/address/0x78A6DfC16BD166f86F0263B1Eec3c697372d8ab6) |
| ServiceRegistry | [`0x7896Dba19A72278d66C9f0640262C511D24CB871`](https://basescan.org/address/0x7896Dba19A72278d66C9f0640262C511D24CB871) |
| MachineAccountFactory | [`0x24f2f3536F65CA2AE36136E3B217a390251a1a90`](https://basescan.org/address/0x24f2f3536F65CA2AE36136E3B217a390251a1a90) |

- Governance (owner): `0x08F3b58CACDd16Bc6B71cAfC16b7886F3205E27d`
- Treasury (fees):    `0x08F3b58CACDd16Bc6B71cAfC16b7886F3205E27d`
- ServiceRegistry authorized as commerce recorder: yes
- Settlement asset (canonical USDC on Base): `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

### Post-launch checklist
- [x] Verify contracts on BaseScan (all three verified, source public)
- [x] Wire live addresses into the marketing site's "LIVE" badges
- [ ] Migrate governance + treasury to a Safe before inviting outside fleets
- [ ] Register the first machines and a demo service (dogfood with small amounts)
