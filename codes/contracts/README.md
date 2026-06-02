# Contracts

Solidity sources, Hardhat config, deploy scripts, and tests for the
anon-poll stack (`PollRegistry`, `ZkAnonVoting`, `ZkBlindVoting`,
`ZkAirdrop`, plus the Semaphore + PoseidonT3 dependencies).

## Local development

```bash
npm install
npm run compile
npm test
npm run node                     # in one terminal
npm run deploy:local             # in another
```

`deploy:local` deploys the full stack (with `MockSemaphoreVerifier`,
which accepts any proof — local dev only) and writes the resulting
addresses into `codes/contracts/deployed-addresses.json`, keyed by
chain ID. Re-deploying to a different network merges into the same
file rather than overwriting it.

## Deploy to Sepolia

The Sepolia path is wired into `hardhat.config.ts` and `scripts/deploy.ts`,
but the real `SemaphoreVerifier` is not yet wired (see `P4-23` / `P4-24`
in `docs/improvements/findings.md`). Until that lands, `deploy:sepolia`
will refuse to run — the script throws rather than letting
`MockSemaphoreVerifier` end up on a public network.

When real-verifier wiring lands, the runbook is:

1. **Fund a deployer account.** Grab Sepolia ETH from a faucet
   (e.g. <https://sepoliafaucet.com>, <https://www.alchemy.com/faucets/ethereum-sepolia>).
2. **Configure env vars.** Copy `.env.example` to `.env` and fill in:
   - `SEPOLIA_RPC_URL` — Alchemy/Infura/QuickNode endpoint.
   - `DEPLOYER_PRIVATE_KEY` — the funded account's private key (no `0x` is required by hardhat,
     but the template includes it for clarity).
   - `ETHERSCAN_API_KEY` — used by `npx hardhat verify` to publish sources.
3. **Deploy.**
   ```bash
   USE_REAL_VERIFIER=true npm run deploy:sepolia
   ```
   The script prints all deployed addresses and merges them into
   `codes/contracts/deployed-addresses.json` under the
   `"11155111"` (Sepolia) key.
4. **(Optional) Verify sources on Etherscan.**
   ```bash
   npx hardhat verify --network sepolia <contract-address> [constructor-args...]
   ```
   `@nomicfoundation/hardhat-verify` ships with `hardhat-toolbox`, so no
   extra install is needed.

## Frontend wiring

The frontend reads addresses from the chainId-keyed
`deployed-addresses.json` based on `VITE_NETWORK`
(`hardhat` → `31337`, `sepolia` → `11155111`). See
`codes/frontend/.env.example` for the matching env vars.
