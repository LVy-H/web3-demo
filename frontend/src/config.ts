import { http, createConfig } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { metaMask, mock } from 'wagmi/connectors'
import deployedAddresses from './deployed-addresses.json'

export const config = createConfig({
    chains: [hardhat, localhost],
    connectors: [
        metaMask(),
        mock({
            accounts: [
                '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266', // Hardhat local account 0
            ],
        }),
    ],
    transports: {
        [hardhat.id]: http('http://127.0.0.1:8545'),
        [localhost.id]: http('http://127.0.0.1:8545'),
    },
})

// Contract details dynamically set
export const FACTORY_ADDRESS = deployedAddresses.FACTORY_ADDRESS as `0x${string}`;
export const AIRDROP_ADDRESS = deployedAddresses.AIRDROP_ADDRESS as `0x${string}`;
