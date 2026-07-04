import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import {
  createPublicClient,
  http,
  parseEventLogs,
  type Hex,
  type PublicClient,
} from "viem";
import { artifacts } from "./contracts.js";

/**
 * Servo paywall gateway: an x402-style HTTP 402 payment wall in front of a
 * machine-payable service.
 *
 * Flow (onchain settlement rail):
 *   1. Client requests the resource with no payment proof.
 *      -> 402 Payment Required + JSON payment requirements (service id, price,
 *         token, settlement contract).
 *   2. The machine pays onchain: MachineAccount.purchase(serviceId), which
 *      settles through the ServiceRegistry and emits a ServiceReceipt.
 *   3. Client retries with header `x-payment: <txHash>`.
 *      -> Gateway verifies the receipt onchain (correct service, success,
 *         not replayed) and serves the resource.
 *
 * The same gateway holds a facilitator key in production to mirror pure-x402
 * (offchain-settled) payments via ServiceRegistry.recordExternalReceipt.
 */

export interface GatewayConfig {
  rpcUrl: string;
  serviceRegistry: Hex;
  serviceId: bigint;
  port: number;
  /** Human-readable description advertised in the 402 body. */
  description: string;
  /** Produces the paid resource once payment is verified. */
  resource: (req: IncomingMessage, payment: VerifiedPayment) => unknown;
}

export interface VerifiedPayment {
  txHash: Hex;
  buyerMid: bigint;
  amount: bigint;
  token: Hex;
}

interface ServiceQuote {
  token: Hex;
  payTo: Hex;
  price: bigint;
}

export class PaywallGateway {
  readonly config: GatewayConfig;
  private client: PublicClient;
  private consumed = new Set<string>(); // replay protection
  private server: Server | undefined;

  constructor(config: GatewayConfig) {
    this.config = config;
    this.client = createPublicClient({ transport: http(config.rpcUrl) });
  }

  async quote(): Promise<ServiceQuote> {
    const [token, payTo, price] = (await this.client.readContract({
      address: this.config.serviceRegistry,
      abi: artifacts.ServiceRegistry.abi,
      functionName: "quote",
      args: [this.config.serviceId],
    })) as [Hex, Hex, bigint];
    return { token, payTo, price };
  }

  /** x402-style payment requirements advertised with the 402 status. */
  private async paymentRequired(res: ServerResponse) {
    const q = await this.quote();
    res.writeHead(402, { "content-type": "application/json" });
    res.end(
      JSON.stringify({
        x402Version: 1,
        error: "payment required",
        accepts: [
          {
            scheme: "servo-onchain",
            description: this.config.description,
            serviceId: this.config.serviceId.toString(),
            settlement: this.config.serviceRegistry,
            asset: q.token,
            amount: q.price.toString(),
            payTo: q.payTo,
            instructions:
              "Settle via MachineAccount.purchase(serviceId), then retry with header x-payment: <txHash>",
          },
        ],
      }),
    );
  }

  /** Verify an onchain settlement: correct service, successful tx, unconsumed. */
  async verifyPayment(txHash: Hex): Promise<VerifiedPayment | { error: string }> {
    if (this.consumed.has(txHash.toLowerCase())) return { error: "payment already consumed" };

    let receipt;
    try {
      receipt = await this.client.getTransactionReceipt({ hash: txHash });
    } catch {
      return { error: "transaction not found" };
    }
    if (receipt.status !== "success") return { error: "transaction reverted" };

    const logs = parseEventLogs({
      abi: artifacts.ServiceRegistry.abi,
      eventName: "ServiceReceipt",
      logs: receipt.logs,
    }).filter(
      (l) =>
        l.address.toLowerCase() === this.config.serviceRegistry.toLowerCase() &&
        (l.args as { serviceId: bigint }).serviceId === this.config.serviceId,
    );
    if (logs.length === 0) return { error: "no ServiceReceipt for this service in tx" };

    const args = logs[0].args as {
      serviceId: bigint;
      buyerMid: bigint;
      providerMid: bigint;
      token: Hex;
      amount: bigint;
    };

    this.consumed.add(txHash.toLowerCase());
    return { txHash, buyerMid: args.buyerMid, amount: args.amount, token: args.token };
  }

  start(): Promise<void> {
    this.server = createServer(async (req, res) => {
      try {
        const payment = req.headers["x-payment"];
        if (!payment || typeof payment !== "string") {
          await this.paymentRequired(res);
          return;
        }
        const verified = await this.verifyPayment(payment as Hex);
        if ("error" in verified) {
          res.writeHead(402, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: verified.error }));
          return;
        }
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify(this.config.resource(req, verified)));
      } catch (err) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: String(err) }));
      }
    });
    return new Promise((resolve) => this.server!.listen(this.config.port, resolve));
  }

  stop(): Promise<void> {
    return new Promise((resolve, reject) =>
      this.server ? this.server.close((e) => (e ? reject(e) : resolve())) : resolve(),
    );
  }
}
