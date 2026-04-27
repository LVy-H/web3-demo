# Releasing

> **Status: PROPOSAL.** This describes the release process we *want*. Today, only `local` is real — the testnet/mainnet flows are placeholders to fill in when we get there.

## Release types

| Type | Network | Audience | Frequency | Reversible? |
|------|---------|----------|-----------|-------------|
| **Local** | Hardhat | Devs only | Every `npm run deploy:local` | Yes — addresses reset on node restart |
| **Testnet** | Sepolia | Public devs / testers | Per minor or major | Yes — abandon and redeploy |
| **Mainnet** | Mainnet (Ethereum or L2) | End users | Per major; rare | **No** — every deployment is permanent. Treat with care. |

## Release checklist (apply to every type, scaling rigor)

### Pre-release

- [ ] All P0 items closed in `improvements/findings.md`
- [ ] All P1 items closed (mainnet only — recommended for testnet)
- [ ] CI green on `main`
- [ ] No uncommitted changes on the release branch
- [ ] CHANGELOG.md has an `## [Unreleased]` section with the actual changes
- [ ] If contracts changed: ABIs regenerated and committed
- [ ] If contracts changed: tests pass under `npm test`
- [ ] Mainnet only: external audit completed, threat model document up to date
- [ ] Mainnet only: owner is a multisig, not an EOA

### Cut the release

1. Decide the version number per `VERSIONING.md`.
2. Update `CHANGELOG.md`: rename `## [Unreleased]` → `## [vX.Y.Z] — YYYY-MM-DD`, add a fresh empty `## [Unreleased]` above it.
3. Update `package.json` `version` in both `codes/contracts/` and `codes/frontend/`.
4. If applicable, update the `VERSION` constant on each contract (proposed; skip if not adopted).
5. Commit: `chore: release vX.Y.Z`.
6. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
7. Push the commit and the tag.

### Deploy

#### Local (Hardhat)
```bash
cd codes/contracts
npm run node              # Terminal 1
npm run deploy:local      # Terminal 2 — overwrites deployed-addresses.json
```
That's it. Addresses are deterministic; the file is gitignored or rewritten per run.

#### Testnet (Sepolia — proposed flow)
```bash
cd codes/contracts
PRIVATE_KEY=... RPC_URL=https://sepolia.infura.io/v3/... npm run deploy:sepolia
```
*(`deploy:sepolia` script does not exist yet — add it as part of [P3-19] and [P4-22].)*

After deploy:
- [ ] Verify each contract on Etherscan
- [ ] Commit `deployed-addresses.sepolia.json` to the repo
- [ ] Test the full happy path against the testnet frontend
- [ ] Document the deployed addresses in CHANGELOG entry

#### Mainnet (proposed flow)
Add **every** safeguard for testnet plus:
- [ ] Deployment runs from a hardware wallet, not a hot key
- [ ] Owner is set to a Gnosis Safe or equivalent multisig before any module is registered
- [ ] Real `SemaphoreVerifier` (NOT `MockSemaphoreVerifier`) — verify the deploy script picks the real one
- [ ] SNARK artifacts bundled with the frontend, not fetched from a third-party CDN at runtime ([P4-24])
- [ ] Announce the deployment with addresses + commit hash before users interact

### Post-release

- [ ] Tag-pushed status mentioned in STATUS.md
- [ ] Old `## [Unreleased]` section moved into the dated CHANGELOG entry
- [ ] FOCUS.md cleared and the next iteration's goal written
- [ ] Frontend rebuilt and deployed (if applicable) — usually a Vercel / Netlify push or a static-site upload; document the host once chosen

## Rollback

| Network | Possible? | How |
|---------|-----------|-----|
| Local | Yes | Restart `npm run node` |
| Testnet | Yes | Mark old addresses as deprecated in `deployed-addresses.sepolia.json`, deploy fresh, update frontend |
| Mainnet | **No** | The contract stays. You can register a new module impl for new polls (existing polls still use the old impl forever — that's the EIP-1167 trade-off). For a fully broken contract, you can only stop pointing to it from the registry and announce the deprecation. |

## What to do if a deployment fails mid-script

The deploy script is sequential. If it fails partway:

1. **Do not retry the whole script** — it'll deploy a second `Semaphore`, second `PollRegistry`, etc.
2. Inspect the partial output (`hardhat-node.log` or stdout).
3. Either (a) abandon and start over (local only), or (b) write a one-off resume script that picks up from the failed step and reuses already-deployed addresses.
4. Once recovered, file an entry in `improvements/findings.md` so we make the script idempotent.

## Communication

- Internal: STATUS.md update + a message in your shared channel
- External (testnet+): a tagged GitHub release with CHANGELOG excerpt
- Mainnet: same plus an announcement with the audit report attached
