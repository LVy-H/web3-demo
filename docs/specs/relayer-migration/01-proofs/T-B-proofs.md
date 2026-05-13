# T-B Proof Summary

Task: Port Express.js relayer service from `archive/origin-relayer-prototype`
into `codes/relayer/` and extend `codes/contracts/scripts/copyAbis.ts` to
populate the relayer's ABI directory.

Base branch: `dev/lvh` @ `43b1753` (T-A landed).

## Validation gates

| Gate | Command | Status | Artifact |
|------|---------|--------|----------|
| 1 | `cd codes/relayer && npm install --ignore-scripts` | PASS | `T-B-01-npm-install.txt` |
| 2 | `cd codes/relayer && npx tsc --noEmit` (after copyAbis) | PASS | `T-B-02-tsc-noemit.txt` |
| 3 | `cd codes/contracts && npm run copy-abis` | PASS | `T-B-03-copyabis.txt` |
| 4 | build + `node -e "require('./dist/index.js')"` | PASS | `T-B-04-build-and-import.txt` |

## Files created (`codes/relayer/`)

- `Dockerfile` — verbatim from `e972c33` (node:lts + curl for healthcheck entrypoint)
- `docker-entrypoint.sh` — verbatim from `e972c33` except service name `contracts` → `hardhat` to match the brief's compose service naming
- `.env.example` — verbatim from archive
- `package.json` — archive deps + added `build` (tsc), `relay` (node dist/index.js) scripts
- `package-lock.json` — verbatim from archive
- `tsconfig.json` — verbatim from archive (already strict, ES2020, `outDir: ./dist`)
- `src/{index,relay,validation,wallet}.ts` — verbatim from archive
- `src/config.ts` — archive verbatim EXCEPT default `rpcUrl` changed from `http://127.0.0.1:8545` to `http://hardhat:8545` per brief (env var override `RPC_URL` still wins)
- `src/abi/.gitkeep` — placeholder so the empty directory is tracked

## Files modified

- `codes/contracts/scripts/copyAbis.ts`:
  - Added `ZkAirdrop.json` to the contracts map (was 4, now 5)
  - Now copies to BOTH `codes/frontend/src/abi/` AND `codes/relayer/src/abi/`
  - Each target is skipped silently if its parent `src/` does not exist
    (so a frontend-only checkout still runs the script)

## Deviations from brief

1. **`docker-entrypoint.sh` healthcheck URL.** The brief says "use the e972c33
   version verbatim" for entrypoint, but the archive entrypoint waits on
   `http://contracts:8545` while the brief specifies `http://hardhat:8545`
   as the compose-service default. Changed entrypoint to `hardhat:8545` so
   the healthcheck and the RPC config agree. Documented in commit message.
2. **`codes/frontend/src/abi/ZkAirdrop.json` is now populated** by copyAbis.
   Brief explicitly asks copyAbis to copy "5 needed ABIs" to BOTH frontend
   and relayer; on dev/lvh the frontend abi/ only had 4 (no ZkAirdrop).
   This is the natural side-effect of complying with the brief's wording.
   The generated file is not committed (frontend abi/ files are git-tracked
   as build outputs; that pattern already exists for the other 4 — T-B
   leaves the existing 4 untouched and does not pre-add ZkAirdrop.json
   to git, since copyAbis is the source of truth).

## Security sanitization

Scanned all `T-B-*` proof files for: `sk-`, `pk_`, `api_key`, `apiKey`,
`Bearer `, JWT, `password=`, `secret`, PEM blocks. None found.

The only credential-shaped value anywhere is the well-known Hardhat test
account #0 private key (`0xac0974…`) shipped as a default in `.env.example`
and `config.ts`. It is intentionally public — the same value appears in
hardhat's own README and is broadcast at chain bootstrap. Not redacted.
