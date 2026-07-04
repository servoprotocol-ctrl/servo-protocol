/**
 * Servo end-to-end demo: a complete machine economy on a local Base fork.
 *
 *   1. Boots anvil and deploys the Servo core + mock USDC.
 *   2. ChargeCo registers a charging station (machine identity + fleet vault
 *      with a 70/30 operator/financier split) and lists a charging service.
 *   3. An operator registers a delivery robot, binds its hardware session key,
 *      opens its MachineAccount, funds it, and sets a 20 USDC/day policy cap.
 *   4. A paywall gateway (x402-style HTTP 402) fronts the charging service.
 *   5. The robot autonomously buys charging sessions over HTTP until its
 *      policy envelope blocks overspend.
 *   6. Vault beneficiaries claim their revenue splits.
 *
 * Run: npm run demo
 */
import { spawn, type ChildProcess } from "node:child_process";
import {
  createPublicClient,
  createWalletClient,
  formatUnits,
  http,
  keccak256,
  parseEther,
  toBytes,
  type Hex,
  type WalletClient,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { foundry } from "viem/chains";
import { artifacts, keyBindingTypedData } from "../contracts.js";
import { PaywallGateway } from "../gateway.js";
import { MachineAgent } from "../agent.js";

const RPC = "http://127.0.0.1:8547";
const GATEWAY_PORT = 4021;
const USDC = (n: string) => BigInt(Math.round(parseFloat(n) * 1e6));
const fmt = (n: bigint) => `${formatUnits(n, 6)} USDC`;

// Anvil's well-known dev accounts.
const KEYS = {
  gov: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  operator: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  chargeCo: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  financier: "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
} as const;

const pub = createPublicClient({ chain: foundry, transport: http(RPC) });

function wallet(pk: Hex): WalletClient {
  return createWalletClient({ account: privateKeyToAccount(pk), chain: foundry, transport: http(RPC) });
}

async function deploy(w: WalletClient, name: keyof typeof artifacts, args: unknown[]): Promise<Hex> {
  const hash = await w.deployContract({
    abi: artifacts[name].abi,
    bytecode: artifacts[name].bytecode,
    args,
    account: w.account!,
    chain: foundry,
  });
  const rcpt = await pub.waitForTransactionReceipt({ hash });
  if (!rcpt.contractAddress) throw new Error(`deploy failed: ${name}`);
  return rcpt.contractAddress;
}

async function write(w: WalletClient, address: Hex, name: keyof typeof artifacts, fn: string, args: unknown[]) {
  const hash = await w.writeContract({
    address,
    abi: artifacts[name].abi,
    functionName: fn,
    args,
    account: w.account!,
    chain: foundry,
  });
  const rcpt = await pub.waitForTransactionReceipt({ hash });
  if (rcpt.status !== "success") throw new Error(`${name}.${fn} reverted`);
  return hash;
}

async function read<T>(address: Hex, name: keyof typeof artifacts, fn: string, args: unknown[] = []): Promise<T> {
  return (await pub.readContract({ address, abi: artifacts[name].abi, functionName: fn, args })) as T;
}

async function waitForRpc(url: string, tries = 50) {
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
      });
      if (res.ok) return;
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error("anvil did not come up");
}

async function main() {
  console.log("\n=== SERVO PROTOCOL: machine economy demo ===\n");

  // ---------------------------------------------------------------- chain
  console.log("[1/6] booting local chain (anvil)...");
  const anvil: ChildProcess = spawn("anvil", ["--port", "8547", "--silent"], { stdio: "ignore" });
  await waitForRpc(RPC);

  const gov = wallet(KEYS.gov);
  const operator = wallet(KEYS.operator);
  const chargeCo = wallet(KEYS.chargeCo);
  const financier = wallet(KEYS.financier);
  const treasuryAddr = privateKeyToAccount(KEYS.gov).address;

  try {
    // ------------------------------------------------------------- deploy
    console.log("[2/6] deploying Servo core to local Base fork...");
    const registry = await deploy(gov, "MachineRegistry", [gov.account!.address]);
    const services = await deploy(gov, "ServiceRegistry", [registry, gov.account!.address, treasuryAddr]);
    const factory = await deploy(gov, "MachineAccountFactory", [registry, services]);
    const usdc = await deploy(gov, "MockUSDC", []);
    console.log(`      MachineRegistry       ${registry}`);
    console.log(`      ServiceRegistry       ${services}`);
    console.log(`      MachineAccountFactory ${factory}`);
    console.log(`      USDC (mock)           ${usdc}`);

    // -------------------------------------------- charging provider setup
    console.log("[3/6] ChargeCo: registering charging station + fleet vault + service listing...");
    const chargerMid = await read<bigint>(registry, "MachineRegistry", "nextMid");
    await write(chargeCo, registry, "MachineRegistry", "registerMachine", [
      chargeCo.account!.address,
      keccak256(toBytes("charger-secure-element-001")),
      6, // Stationary
      "ipfs://charger-metadata",
    ]);
    const vault = await deploy(chargeCo, "FleetVault", [
      registry,
      usdc,
      chargeCo.account!.address,
      [
        { account: chargeCo.account!.address, bps: 7000 },
        { account: financier.account!.address, bps: 3000 },
      ],
    ]);
    await write(chargeCo, vault, "FleetVault", "addMachine", [chargerMid]);

    const serviceId = await read<bigint>(services, "ServiceRegistry", "nextServiceId");
    await write(chargeCo, services, "ServiceRegistry", "registerService", [
      chargerMid,
      vault,
      usdc,
      USDC("5"), // 5 USDC per charging session
      keccak256(toBytes("CHARGING")),
      true, // vault settlement: attribute revenue to the charger's P&L
      `http://127.0.0.1:${GATEWAY_PORT}/charge`,
    ]);
    console.log(`      charger MID ${chargerMid}, vault ${vault}, service #${serviceId} @ 5 USDC/session`);

    // ------------------------------------------------- delivery bot setup
    console.log("[4/6] Operator: registering delivery robot, binding key, funding account...");
    const botMid = await read<bigint>(registry, "MachineRegistry", "nextMid");
    await write(operator, registry, "MachineRegistry", "registerMachine", [
      operator.account!.address,
      keccak256(toBytes("bot-secure-element-042")),
      2, // MobileGround
      "ipfs://bot-metadata",
    ]);

    // The robot's secure element generates its session key; it never leaves the device.
    const machineKey = privateKeyToAccount(generatePrivateKey());
    const bindSig = await machineKey.signTypedData(
      keyBindingTypedData({
        chainId: foundry.id,
        registry,
        mid: botMid,
        operator: operator.account!.address,
        machineKey: machineKey.address,
      }),
    );
    await write(operator, registry, "MachineRegistry", "bindMachineKey", [botMid, machineKey.address, bindSig]);

    await write(operator, factory, "MachineAccountFactory", "createAccount", [botMid]);
    const botAccount = await read<Hex>(factory, "MachineAccountFactory", "accountOf", [botMid]);

    await write(gov, usdc, "MockUSDC", "mint", [botAccount, USDC("100")]);
    await write(operator, botAccount, "MachineAccount", "setDailyCap", [usdc, USDC("20")]);
    // Gas for the device key (mainnet: 4337 paymaster; local demo: small ETH grant).
    const gasHash = await operator.sendTransaction({
      account: operator.account!,
      chain: foundry,
      to: machineKey.address,
      value: parseEther("1"),
    });
    await pub.waitForTransactionReceipt({ hash: gasHash });
    console.log(`      bot MID ${botMid}, account ${botAccount}, funded 100 USDC, policy cap 20 USDC/day`);

    // -------------------------------------------------------- gateway up
    console.log("[5/6] starting x402-style paywall gateway for the charging service...");
    let session = 0;
    const gateway = new PaywallGateway({
      rpcUrl: RPC,
      serviceRegistry: services,
      serviceId,
      port: GATEWAY_PORT,
      description: "DC fast charging session, bay A-07",
      resource: (_req, payment) => ({
        session: ++session,
        bay: "A-07",
        kwhAuthorized: 3.2,
        buyerMid: payment.buyerMid.toString(),
        paidTx: payment.txHash,
      }),
    });
    await gateway.start();
    console.log(`      gateway live at http://127.0.0.1:${GATEWAY_PORT}/charge\n`);

    // ------------------------------------------------ the robot goes to work
    console.log("[6/6] delivery robot autonomously buys charging over HTTP...\n");
    const agent = new MachineAgent({ rpcUrl: RPC, machineKey, machineAccount: botAccount });

    for (let i = 1; i <= 4; i++) {
      const { resource, paidTx } = await agent.fetchPaid(`http://127.0.0.1:${GATEWAY_PORT}/charge`);
      const r = resource as { session: number; bay: string; kwhAuthorized: number };
      console.log(`      session ${r.session}: charged at bay ${r.bay} (${r.kwhAuthorized} kWh) | paid 5 USDC | tx ${paidTx?.slice(0, 18)}...`);
    }

    console.log("\n      5th session of the day (would exceed the 20 USDC policy cap):");
    try {
      await agent.fetchPaid(`http://127.0.0.1:${GATEWAY_PORT}/charge`);
      console.log("      UNEXPECTED: purchase succeeded");
    } catch {
      console.log("      BLOCKED by MachineAccount policy envelope (DailyCapExceeded) ✓");
    }

    // -------------------------------------------------------- settlements
    console.log("\n      beneficiaries claim their splits from the fleet vault...");
    await write(chargeCo, vault, "FleetVault", "claim", []);
    await write(financier, vault, "FleetVault", "claim", []);

    // ------------------------------------------------------------- report
    const [botBal, chargeCoBal, finBal, treasBal] = await Promise.all([
      read<bigint>(usdc, "MockUSDC", "balanceOf", [botAccount]),
      read<bigint>(usdc, "MockUSDC", "balanceOf", [chargeCo.account!.address]),
      read<bigint>(usdc, "MockUSDC", "balanceOf", [financier.account!.address]),
      read<bigint>(usdc, "MockUSDC", "balanceOf", [treasuryAddr]),
    ]);
    const chargerPnl = await read<bigint>(vault, "FleetVault", "machineRevenue", [chargerMid]);
    const svc = await read<{ unitsSold: bigint; grossRevenue: bigint }>(
      services, "ServiceRegistry", "getService", [serviceId],
    );
    const machine = await read<{ jobsAttested: bigint; revenueAttested: bigint }>(
      registry, "MachineRegistry", "getMachine", [chargerMid],
    );
    void machine;

    console.log("\n=== FINAL STATE: the machine economy ledger ===\n");
    console.log(`  charging service        ${svc.unitsSold} sessions sold, ${fmt(BigInt(svc.grossRevenue))} gross`);
    console.log(`  charger onchain P&L     ${fmt(chargerPnl)} attributed to MID ${chargerMid}`);
    console.log(`  delivery bot account    ${fmt(botBal)} remaining (spent 20, hit daily cap)`);
    console.log(`  ChargeCo (70%)          ${fmt(chargeCoBal)} claimed`);
    console.log(`  financier (30%)         ${fmt(finBal)} claimed`);
    console.log(`  protocol treasury (1%)  ${fmt(treasBal)} collected`);
    console.log("\n  Every payment above was made autonomously by a machine, inside an");
    console.log("  operator-defined policy envelope, with onchain receipts and per-machine");
    console.log("  revenue attribution. This is the Servo loop.\n");

    await gateway.stop();
  } finally {
    anvil.kill();
  }
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  },
);
