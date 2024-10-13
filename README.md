# [Untron](https://untron.finance) V1

Smart contracts for Untron V1 protocol

![](/static/banner.png)

## High-level overview

Untron V1 is a B2B P2P marketplace for exchanging USDT on Tron Network into USDT on ZKsync Era, [inspired by ZKP2P](https://zkp2p.xyz). It has a native [LI.FI](https://li.fi) integration, allowing to automatically swap USDT on Era into any other token on any Ethereum L2 and more. Ethereum-based projects, such as wallets, who are willing to enable USDT Tron deposits, can integrate Untron V1 and create orders on behalf of their users.

Untron V1 is the first protocol of the two, along with [Untron Intents](https://github.com/ultrasoundlabs/untron-intents), forming the larger [Untron project](https://untron.finance). It's described in high level in ["P2P ZK Light Client Bridge between Tron and Ethereum L2s" (Hook, 2024)](https://ethresear.ch/t/p2p-zk-light-client-bridge-between-tron-and-ethereum-l2s/19931).

All Untron protocols are powered by [Untron ZK Engine](https://github.com/ultrasoundlabs/untron)—a Rust program implementing a minimal Tron node with an internal state used by the protocols. It's compiled and executed using SP1 zkVM to generate ZK proofs of Tron blockchain and all necessary deposits and transfers.

```mermaid
flowchart TD

    subgraph Initialization
        Start([Start])
        UserL2[User on L2]
        ProviderL2[Provider on L2]
        FulfillerL2[Fulfiller on L2]
        UntronCore[UntronCore Contract]
        ReceiverTron[Provider's Receiver on Tron]
    end

    Start --> UserL2

    subgraph OrderCreation
        UserL2 --> A1[Calls createOrder function]
        A1 --> UntronCore
        UntronCore --> A2[Validate Order Parameters]
        A2 --> A3[Collect Collateral from User]
        A3 --> A4[Store Order in Contract]
        A4 --> A5[Emit OrderCreated Event]
    end

    subgraph UserAction
        A5 --> UserL2
        UserL2 --> B1[Send USDT on Tron to Receiver]
        B1 --> ReceiverTron
    end

    subgraph Fulfillment
        B1 --> F1[Fulfiller Monitors Tron Network]
        F1 --> F2{USDT Transfer Detected?}
        F2 -- Yes --> F3[Calls fulfill function with Order IDs]
        F3 --> UntronCore
        UntronCore --> F4[Lock Fulfiller's Funds]
        F3 --> F5[Fulfiller Sends USDT on L2 to User]
        F5 --> UserL2
    end

    subgraph ZKProofGeneration
        F5 --> Z1[Off-chain ZK Proof Generation]
        Z1 --> Z2[Generate ZK Proof]
        Z2 --> Relayer[Relayer]
        Relayer --> Z3[Calls closeOrders function with Proof]
        Z3 --> UntronCore
        UntronCore --> Z4[Verify ZK Proof]
    end

    subgraph Settlement
        Z4 --> S1{Proof Valid?}
        S1 -- Yes --> S2[Update Contract State]
        S2 --> S3[Release Provider's Locked Liquidity]
        S2 --> S4[Reimburse Fulfiller and Pay Fees]
        S2 --> S5[Emit OrderClosed Event]
        S5 --> End([End])
        S1 -- No --> S6[Revert or Handle Error]
    end
```

## Integrate

For integration, please proceed to [our documentation](https://ultrasoundlabs.github.io/untron-docs). You can also contact us at [contact@untron.finance](mailto:contact@untron.finance).

## License

Untron project and all protocols it consists of are licensed under BUSL license by Ultrasound Labs LLC. For more details, please refer to [LICENSE](/LICENSE). Some of the project's dependencies are licensed under MIT and Apache-2.0 licenses.
