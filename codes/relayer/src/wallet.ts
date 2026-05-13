import { ethers } from "ethers";
import { config } from "./config";

let provider: ethers.JsonRpcProvider;
let wallet: ethers.Wallet;

export function getProvider(): ethers.JsonRpcProvider {
    if (!provider) {
        provider = new ethers.JsonRpcProvider(config.rpcUrl);
    }
    return provider;
}

export function getRelayerWallet(): ethers.Wallet {
    if (!wallet) {
        wallet = new ethers.Wallet(config.privateKey, getProvider());
    }
    return wallet;
}

export async function getRelayerInfo(): Promise<{
    address: string;
    balance: string;
}> {
    const w = getRelayerWallet();
    const balance = await getProvider().getBalance(w.address);
    return {
        address: w.address,
        balance: ethers.formatEther(balance),
    };
}
