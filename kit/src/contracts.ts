import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Abi, Hex } from "viem";

/** Loads ABI + creation bytecode from the Foundry build output in ../contracts. */

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "contracts", "out");

export interface Artifact {
  abi: Abi;
  bytecode: Hex;
}

function load(source: string, name: string): Artifact {
  const raw = JSON.parse(readFileSync(join(OUT_DIR, source, `${name}.json`), "utf8"));
  return { abi: raw.abi as Abi, bytecode: raw.bytecode.object as Hex };
}

export const artifacts = {
  MachineRegistry: load("MachineRegistry.sol", "MachineRegistry"),
  ServiceRegistry: load("ServiceRegistry.sol", "ServiceRegistry"),
  MachineAccountFactory: load("MachineAccountFactory.sol", "MachineAccountFactory"),
  MachineAccount: load("MachineAccount.sol", "MachineAccount"),
  FleetVault: load("FleetVault.sol", "FleetVault"),
  MockUSDC: load("MockUSDC.sol", "MockUSDC"),
} as const;

/** EIP-712 typed data for binding a machine session key to its MID. */
export function keyBindingTypedData(params: {
  chainId: number;
  registry: Hex;
  mid: bigint;
  operator: Hex;
  machineKey: Hex;
}) {
  return {
    domain: {
      name: "ServoMachineRegistry",
      version: "1",
      chainId: params.chainId,
      verifyingContract: params.registry,
    },
    types: {
      KeyBinding: [
        { name: "mid", type: "uint256" },
        { name: "operator", type: "address" },
        { name: "machineKey", type: "address" },
      ],
    },
    primaryType: "KeyBinding" as const,
    message: {
      mid: params.mid,
      operator: params.operator,
      machineKey: params.machineKey,
    },
  };
}
