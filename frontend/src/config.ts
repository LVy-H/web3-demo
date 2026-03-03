import { http, createConfig } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { metaMask } from 'wagmi/connectors'

export const config = createConfig({
    chains: [hardhat, localhost],
    connectors: [
        metaMask(),
    ],
    transports: {
        [hardhat.id]: http('http://127.0.0.1:8545'),
        [localhost.id]: http('http://127.0.0.1:8545'),
    },
})

// Contract details
export const CONTRACT_ADDRESS = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9";
