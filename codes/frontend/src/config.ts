import { http, createConfig } from 'wagmi'
import { hardhat, localhost, sepolia } from 'wagmi/chains'
import type { Chain } from 'wagmi/chains'
import { metaMask, mock } from 'wagmi/connectors'
import deployedAddresses from './deployed-addresses.json'

// ── Network selection ───────────────────────────────────────────────
// VITE_NETWORK = "hardhat" (default) | "sepolia"
//   hardhat → chainId 31337, default RPC http://127.0.0.1:8545
//   sepolia → chainId 11155111, VITE_RPC_URL is required
// VITE_RPC_URL overrides the default RPC for the active network.
type NetworkName = 'hardhat' | 'sepolia'

const VITE_NETWORK = (import.meta.env.VITE_NETWORK as NetworkName | undefined) ?? 'hardhat'

const NETWORK_CONFIG: Record<NetworkName, { chain: Chain; chainId: number; defaultRpc: string | null }> = {
    hardhat: { chain: hardhat, chainId: 31337, defaultRpc: 'http://127.0.0.1:8545' },
    sepolia: { chain: sepolia, chainId: 11155111, defaultRpc: null },
}

const active = NETWORK_CONFIG[VITE_NETWORK]
if (!active) {
    throw new Error(`Unknown VITE_NETWORK="${VITE_NETWORK}". Expected "hardhat" or "sepolia".`)
}

const RPC_URL = import.meta.env.VITE_RPC_URL || active.defaultRpc
if (!RPC_URL) {
    throw new Error(
        `VITE_RPC_URL is required when VITE_NETWORK="${VITE_NETWORK}" (no default RPC for this network).`
    )
}

// Hardhat dev also exposes itself as `localhost`; keep both registered so the
// existing dev workflow (and the mock connector) keeps working.
// Two branches kept separate so wagmi can infer the chain-tuple → transports
// mapping cleanly (a single createConfig with a union of chain tuples breaks
// the inferred Record<chainId, Transport>).
const connectors = [
    metaMask(),
    ...(import.meta.env.DEV && VITE_NETWORK === 'hardhat'
        ? [
              mock({
                  accounts: ['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'],
              }),
          ]
        : []),
]

export const config = VITE_NETWORK === 'hardhat'
    ? createConfig({
          chains: [hardhat, localhost],
          connectors,
          transports: {
              [hardhat.id]: http(RPC_URL),
              [localhost.id]: http(RPC_URL),
          },
      })
    : createConfig({
          chains: [sepolia],
          connectors,
          transports: {
              [sepolia.id]: http(RPC_URL),
          },
      })

// ── Deployed addresses (chainId-keyed) ──────────────────────────────
type AddressBook = {
    REGISTRY_ADDRESS: string
    SEMAPHORE_ADDRESS: string
    ANON_VOTING_IMPL: string
    BLIND_VOTING_IMPL: string
    AIRDROP_ADDRESS: string
}

const allAddresses = deployedAddresses as Record<string, AddressBook>
const addresses = allAddresses[String(active.chainId)]
if (!addresses) {
    throw new Error(
        `No deployed addresses for chainId ${active.chainId} (VITE_NETWORK="${VITE_NETWORK}"). ` +
        `Run \`npm run deploy:${VITE_NETWORK === 'hardhat' ? 'local' : VITE_NETWORK}\` in codes/contracts first.`
    )
}

export const REGISTRY_ADDRESS = addresses.REGISTRY_ADDRESS as `0x${string}`
export const SEMAPHORE_ADDRESS = addresses.SEMAPHORE_ADDRESS as `0x${string}`
export const AIRDROP_ADDRESS = addresses.AIRDROP_ADDRESS as `0x${string}`

// Gasless relayer base URL. Defaults to the local dev port; override via
// VITE_RELAYER_URL in .env.local for staging/prod or alternate ports.
export const RELAYER_URL = import.meta.env.VITE_RELAYER_URL ?? 'http://localhost:3001';

// Defense-in-depth: a misconfigured env or hostile build-time injection could
// set VITE_RELAYER_URL to `javascript:`, `file://`, or `data:` and turn the
// relayer URL into a foot-gun for fetch / window.open / link rendering. Fail
// fast at module-load instead of letting an unsafe scheme propagate.
if (!/^https?:\/\//.test(RELAYER_URL)) {
    throw new Error(`Invalid RELAYER_URL: must start with http:// or https:// (got "${RELAYER_URL}")`);
}
