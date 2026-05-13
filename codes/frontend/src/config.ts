import { http, createConfig } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { metaMask, mock } from 'wagmi/connectors'
import deployedAddresses from './deployed-addresses.json'

const RPC_URL = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545'

export const config = createConfig({
    chains: [hardhat, localhost],
    connectors: [
        metaMask(),
        mock({
            accounts: ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'],
        }),
    ],
    transports: {
        [hardhat.id]: http(RPC_URL),
        [localhost.id]: http(RPC_URL),
    },
})

export const REGISTRY_ADDRESS = deployedAddresses.REGISTRY_ADDRESS as `0x${string}`;
export const SEMAPHORE_ADDRESS = deployedAddresses.SEMAPHORE_ADDRESS as `0x${string}`;
export const AIRDROP_ADDRESS = deployedAddresses.AIRDROP_ADDRESS as `0x${string}`;

// Gasless relayer base URL. Defaults to the local dev port; override via
// VITE_RELAYER_URL in .env.local for staging/prod or alternate ports.
export const RELAYER_URL = import.meta.env.VITE_RELAYER_URL ?? 'http://localhost:3001';
