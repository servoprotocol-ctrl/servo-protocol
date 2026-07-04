import {
  createPublicClient,
  createWalletClient,
  http,
  type Hex,
  type PrivateKeyAccount,
} from "viem";
import { artifacts } from "./contracts.js";

/**
 * MachineAgent: the client-side payment brain of a robot. Given an HTTP
 * endpoint fronted by a Servo paywall, it:
 *
 *   1. requests the resource,
 *   2. on 402, reads the payment requirements,
 *   3. settles onchain from its MachineAccount using its bound machine key
 *      (subject to the operator's policy envelope),
 *   4. retries with the settlement proof and returns the resource.
 */
export class MachineAgent {
  constructor(
    private readonly opts: {
      rpcUrl: string;
      machineKey: PrivateKeyAccount; // the device's bound session key
      machineAccount: Hex; // its MachineAccount address
    },
  ) {}

  async fetchPaid(url: string): Promise<{ resource: unknown; paidTx?: Hex; amount?: bigint }> {
    const first = await fetch(url);
    if (first.status === 200) return { resource: await first.json() };
    if (first.status !== 402) throw new Error(`unexpected status ${first.status}`);

    const requirements = (await first.json()) as {
      accepts: Array<{ scheme: string; serviceId: string; amount: string }>;
    };
    const offer = requirements.accepts.find((a) => a.scheme === "servo-onchain");
    if (!offer) throw new Error("no servo-onchain payment option offered");

    const paidTx = await this.purchase(BigInt(offer.serviceId));

    const retry = await fetch(url, { headers: { "x-payment": paidTx } });
    if (retry.status !== 200) {
      throw new Error(`payment not accepted: ${retry.status} ${await retry.text()}`);
    }
    return { resource: await retry.json(), paidTx, amount: BigInt(offer.amount) };
  }

  /** Settle a service purchase from the machine's account, signed by its key. */
  async purchase(serviceId: bigint): Promise<Hex> {
    const wallet = createWalletClient({
      account: this.opts.machineKey,
      transport: http(this.opts.rpcUrl),
    });
    const pub = createPublicClient({ transport: http(this.opts.rpcUrl) });

    const chain = await this.chain();
    const hash = await wallet.writeContract({
      chain,
      address: this.opts.machineAccount,
      abi: artifacts.MachineAccount.abi,
      functionName: "purchase",
      args: [serviceId],
    });
    const receipt = await pub.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") throw new Error("purchase reverted");
    return hash;
  }

  private async chain() {
    const pub = createPublicClient({ transport: http(this.opts.rpcUrl) });
    const id = await pub.getChainId();
    return {
      id,
      name: `chain-${id}`,
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [this.opts.rpcUrl] } },
    };
  }
}
