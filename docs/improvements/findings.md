# Findings

Detailed entries for every item on the status board ([README.md](./README.md)). Each entry has enough context that a fresh contributor (human or agent) can work it without re-reading the codebase.

## Entry template

```
### <ID> — <title>

**Priority:** P0 | P1 | P2 | P3 | P4
**Status:** Open | In Progress | Done | Won't Fix
**Owner:** —

**Where:** file:line(s)
**Observed:** verified facts (cite cmd or file)
**Why it matters:** impact in plain English
**Repro:** steps to see the issue (if applicable)
**Fix:** concrete approach
**Acceptance:** how to verify the fix landed correctly
**Notes:** links, tradeoffs, open questions
```

---

## P0 — Bugs

### P0-1 — `localStorage['my-nullifier']` is global, not per-poll {#p0-1}

**Priority:** P0
**Status:** Won't Fix — MOOT (the React `Poll.tsx` was deleted 2026-06-02; the
Flutter app keys nullifier state per (poll, commitment) in secure storage).
**Owner:** —

**Where:** `codes/frontend/src/pages/Poll.tsx:185-186, 377`

**Observed:**
- Line 185-186 (in the `useEffect` triggered on `pollAddress` change): `const nullifier = localStorage.getItem('my-nullifier'); if (nullifier) setHasVoted(true);`
- Line 377 (after a successful vote): `localStorage.setItem('my-nullifier', fullProof.nullifier.toString())`
- The key `'my-nullifier'` is a single global slot — not scoped to the poll address.

**Why it matters:** A user who votes on poll A and then opens poll B sees `hasVoted = true` on poll B, gets blocked from voting there even though they're a registered voter on B with no nullifier consumed. UX-broken; not a chain-state bug (the contract still accepts the vote), just a frontend lie.

**Repro:**
1. Cast a vote on any M1 poll. Browser writes `my-nullifier`.
2. Navigate to a different M1 poll.
3. Observe: vote UI is hidden, "you have already voted" state shown, even though you haven't on this poll.

**Fix:** Scope the key. Two changes:
- Line 377 → `localStorage.setItem('my-nullifier-' + pollAddress, fullProof.nullifier.toString())`
- Line 185-186 → `const nullifier = localStorage.getItem('my-nullifier-' + pollAddress); ...`
- Also: in the "Clear identity" handler (~line 517) which calls `localStorage.removeItem('semaphore-identity-' + pollAddress)`, also remove the per-poll nullifier so re-loading the same identity on the same poll re-checks state correctly.

**Acceptance:**
- Manual: vote on poll A, navigate to poll B, vote UI is available on B.
- Test: Playwright E2E in `codes/frontend/tests/e2e.spec.ts` extended with a multi-poll flow that votes on poll A then verifies poll B's UI still shows the vote-cast button (skip if creating multiple deterministic polls in test takes too long; manual repro is acceptable for P0).

**Notes:** Same bug class likely exists for any other global localStorage key. Grep `codes/frontend/src` for `localStorage` and audit each key during this fix.

---

### P0-2 — Module-scope `let group` / `let isGroupSynced` in `Poll.tsx` {#p0-2}

**Priority:** P0
**Status:** Won't Fix — MOOT (React `Poll.tsx` deleted 2026-06-02; the Flutter app
holds per-poll state in scoped ViewModels, no module-level leakage).
**Owner:** —

**Where:** `codes/frontend/src/pages/Poll.tsx:137-138`

**Observed:**
```ts
let group: Group | null = null;
let isGroupSynced = false;
```
declared at module top-level, **outside** the React component. Used inside `syncGroupState` (lines 244-273) and `handleVote` (lines 343-384).

**Why it matters:**
- Persists across `<Poll>` mount/unmount. If you navigate `/poll/A → / → /poll/B`, the old group state from A leaks into B. The `useEffect` at line 181-187 sets `isGroupSynced = false` on `pollAddress` change as a workaround, but `group` itself is not reset.
- Breaks under React StrictMode double-rendering and HMR.
- Module globals in React are an anti-pattern: invisible to React's render cycle, untestable, race-prone.

**Repro:** Hard to reproduce visibly today because `pollAddress` change triggers a forced re-sync. The bug is latent — likely to surface during P2-13 refactor when the module is split.

**Fix:** Extract a `useGroupSync(pollAddress, contractGroupId)` hook in `codes/frontend/src/hooks/useGroupSync.ts`:
```ts
export function useGroupSync(pollAddress: `0x${string}` | undefined, ...) {
  const groupRef = useRef<Group | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);
  const [isSynced, setIsSynced] = useState(false);
  // ... reset on pollAddress change, sync via getLogs
  return { group: groupRef.current, isSyncing, isSynced, sync };
}
```
Replace lines 137-138 + the inline `syncGroupState` function with consumption of the hook.

**Acceptance:**
- `codes/frontend/src/pages/Poll.tsx` no longer has `let` declarations at module scope (grep for `^let ` outside functions).
- Existing E2E `codes/frontend/tests/e2e.spec.ts` still passes.
- Manual: vote on poll A, navigate to poll B, voting on B works correctly (this also exercises the no-leak property).

**Notes:** Pair this with P0-1 — same file, same area, sensible single PR. Coordinate with P2-13 (full Poll.tsx refactor) by either landing P0-2 first as a small, focused fix, or rolling it into the larger P2 work. Recommendation: P0 first, fast.

---

### P0-3 — `ZkAirdrop` has no test file {#p0-3}

**Priority:** P0
**Status:** Done — `codes/contracts/test/ZkAirdrop.test.ts` exists; the full
contracts suite is 109 passing (2026-06-02).
**Owner:** —

**Where:** `codes/contracts/test/` — directory contains `PollRegistry.test.ts`, `ZkAnonVoting.test.ts`, `ZkBlindVoting.test.ts`. No `ZkAirdrop.test.ts`.

**Observed:**
- `ls codes/contracts/test/` confirms three test files only.
- `git log --all --diff-filter=A -- '*ZkAirdrop.test.ts'` returns nothing.
- Contract is fully wired in `scripts/deploy.ts` (deployed + funded with 10 ETH) and reachable from the frontend config (`AIRDROP_ADDRESS` exported from `codes/frontend/src/config.ts:24`), but functionally exercised by zero tests.

**Why it matters:** `ZkAirdrop` handles real ETH payouts. Untested code that moves money is a P0 hazard regardless of how simple it looks. Concrete attack surfaces with no test coverage:
- Replay across airdrops (proof.scope binding)
- Receiver substitution (proof.message binding)
- Double-claim by nullifier reuse
- ETH transfer failure path (`require(success, "Failed to send ETH")`)

**Repro:** None — absence of tests is the issue.

**Fix:** Create `codes/contracts/test/ZkAirdrop.test.ts` with at minimum:
1. **Deployment + initial state:** owner is set, group created, state == `Registration`, balance == 0 ETH initially, `airdropAmount` matches constructor arg.
2. **Funding:** `receive()` accepts ETH; balance increases.
3. **Registration:**
   - `registerMember(commitment)` succeeds in `Registration` state.
   - Multiple commitments can be registered (no admin gate — by design).
   - After `startAirdrop()`, `registerMember` reverts with `"Not in registration phase"`.
4. **Lifecycle:** `startAirdrop()` is owner-only (`"Not owner"` revert from non-owner) and only valid from `Registration` state.
5. **Claim happy path:** Generate a Semaphore identity, register, transition to `Claiming`, build a proof with `scope = address(airdrop)` and `message = uint256(uint160(receiver))`, call `claimAirdrop(receiver, proof)`, assert receiver balance increased by `airdropAmount`, nullifier marked used.
6. **Claim revert paths:**
   - Wrong scope → `"Invalid claim scope"`.
   - Wrong receiver in message → `"Receiver mismatch"`.
   - Reused nullifier → `"Airdrop already claimed by this identity"`.
   - Invalid proof → `"Invalid claim proof"`.
   - Pre-`startAirdrop` → `"Not in claiming phase"`.

**Acceptance:**
- `npx hardhat test test/ZkAirdrop.test.ts` passes locally.
- Test count rises from 17 to 17 + N (target N ≥ 10, one per case above).
- `npm test` (full suite) still green.

**Notes:**
- Tests run against `MockSemaphoreVerifier` (always returns true). The "invalid proof" test must therefore use the real verifier or assert on a different revert reason; document this trade-off in a code comment in the test file. Preferred approach: deploy a separate `Semaphore` instance with the real verifier just for the "invalid proof" test, or skip that single case and cover it under the future P4-23 real-Groth16 nightly run.
- Existing tests use the `time` helper from `@nomicfoundation/hardhat-toolbox/network-helpers` — follow that pattern.
- Use `@semaphore-protocol/identity` and `@semaphore-protocol/proof` (already devDependencies) to build proofs in the test.

---

### P0-4 — Top-level docs describe the old `ZkVotingLottery` design {#p0-4}

**Priority:** P0
**Status:** Done — `INSTRUCTIONS.md` + `ZkVotingAirdrop_System_Workflow.md`
removed; `codes/README.md` rewritten (no lottery refs remain, 2026-06-02).
**Owner:** —

**Where:**
- `codes/README.md`
- `codes/INSTRUCTIONS.md`
- `codes/ZkVotingAirdrop_System_Workflow.md`

**Observed:**
- `codes/README.md` opens with "ZK Ballot & Lottery — PoC" and describes a single contract `ZkVotingLottery.sol` that no longer exists (current contracts are `PollRegistry` + `ZkAnonVoting` + `ZkBlindVoting` + `ZkAirdrop`).
- `codes/INSTRUCTIONS.md` walks through "Generate Local Identity → Submit Commitment On-chain → Close & Draw Lottery" — none of those buttons exist in the UI today.
- `codes/ZkVotingAirdrop_System_Workflow.md` references the lottery contract.
- These three files mislead any new contributor who follows the linked instructions.

**Why it matters:** New contributors (your friend included) will read the README first. If it tells them to look for buttons that don't exist, they'll either get stuck or open issues for non-bugs. Wastes time.

**Fix — pick one of:**

**Option A (recommended): Rewrite `codes/README.md`, delete the other two.**
- New `codes/README.md` content: 30–60 lines covering setup, the 4-terminal local stack, the actual current architecture (registry + clones + 2 modules + standalone airdrop), and a link to `docs/architecture/system-overview.md` for depth.
- `git rm codes/INSTRUCTIONS.md codes/ZkVotingAirdrop_System_Workflow.md`
- Update any cross-link to those files (none currently exist; verify with grep).

**Option B: Rewrite all three to match current architecture.**
- More words, more drift surface. Discouraged unless the team explicitly wants distinct README/INSTRUCTIONS/Workflow docs.

**Acceptance:**
- `grep -ri "ZkVotingLottery\|Submit Commitment\|Close & Draw Lottery" codes/` returns no matches.
- `codes/README.md` references `PollRegistry`, `ZkAnonVoting`, `ZkBlindVoting`, `ZkAirdrop` — verifies it's current.
- `codes/README.md` links to `docs/architecture/system-overview.md`.

**Notes:** Don't update the canonical architecture into `codes/README.md` — keep that file short and link out. Architecture lives in `docs/`.

---

## P1 — Contract security

> Detailed entries land when Sprint 2 is queued. Summaries here so the friend can read the scope ahead of time.

### P1-5 — Replace hand-rolled `_initialized` with OZ `Initializable` {#p1-5}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `ZkAnonVoting.sol`, `ZkBlindVoting.sol`. Both currently use a manual `bool private _initialized` guard.

**Summary:** Import `@openzeppelin/contracts/proxy/utils/Initializable.sol`, inherit, mark `initialize` with `initializer`, and add `_disableInitializers()` in the implementation's constructor so the bare impl can never be initialized directly. Industry-standard pattern; saves 5 lines per contract; gives reinitializer support for free if we later need it.

### P1-6 — Replace ad-hoc `onlyOwner` with OZ `Ownable` / `Ownable2Step` {#p1-6}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** All contracts (`PollRegistry`, `ZkAnonVoting`, `ZkBlindVoting`, `ZkAirdrop`).

**Summary:** Inherit `Ownable` for poll modules, `Ownable2Step` for `PollRegistry` (transferable ownership matters more for the registry). Drop the inline `modifier onlyOwner` and `address public owner` slots — `Ownable` provides both. Note: `IZkPoll` declares `function owner() external view returns (address)` — keep this; OZ's `Ownable` provides it.

### P1-7 — Custom errors instead of revert strings {#p1-7}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** All contracts.

**Summary:** Replace `require(cond, "string")` with `if (!cond) revert NamedError(args);`. Cheaper gas (~50 per revert), structured decoding clientside, clearer at the ABI level. Keep error names stable — once tooling indexes them, renames are breaking.

### P1-8 — Add `ReentrancyGuard` to `ZkAirdrop.claimAirdrop` {#p1-8}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `codes/contracts/contracts/ZkAirdrop.sol:64`

**Summary:** Defense in depth. Current code does external `.call{value: ...}` after setting `isNullifierUsed = true`, so reentrancy can't double-spend the same nullifier — but a `nonReentrant` modifier protects against future code edits that reorder these statements. Cheap and idiomatic.

### P1-9 — Owner escape hatch for unclaimed airdrop ETH {#p1-9}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `codes/contracts/contracts/ZkAirdrop.sol`

**Summary:** No way to recover unclaimed ETH today. Add `endClaiming()` (owner, transitions to a new `Ended` state) + `withdrawUnclaimed(address to)` (owner, only after `endClaiming`). Optionally enforce `block.timestamp > claimDeadline` in `withdrawUnclaimed`. Document the new state machine in `docs/architecture/module-airdrop.md`.

### P1-10 — Unify Solidity pragma {#p1-10}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** All `.sol` files + `hardhat.config.ts`.

**Summary:** Pin to one version. Recommend `0.8.28` (current stable). Drop `^` carets — `pragma solidity 0.8.28;`. Update `hardhat.config.ts`'s `version: "0.8.34"` to match. Compile + run full test suite; should be a no-op.

### P1-11 — `ZkAnonVoting.startVoting` should require ≥1 voter {#p1-11}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `codes/contracts/contracts/ZkAnonVoting.sol:136-144`

**Summary:** Currently requires `options.length >= 2` only. `ZkBlindVoting` requires both options ≥ 2 AND voters ≥ 1. Make M1 consistent: add `require(participantCount >= 1, "Need at least 1 voter");`. One-line change + add a test in `ZkAnonVoting.test.ts`.

### P1-12 — Cap batch size in `registerVoters` {#p1-12}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `codes/contracts/contracts/ZkAnonVoting.sol:117-132`

**Summary:** Loop is unbounded. Owner-only so no DoS-by-stranger, but a careless owner could OOM the block. Add `require(identityCommitments.length <= 100, "Batch too large");`. Frontend should chunk requests above 100. Test the boundary.

---

## P2 — Frontend refactor

### P2-13 — Split `Poll.tsx` (855 LOC) into composed components + hooks {#p2-13}

**Priority:** P2 — **Status:** Open — **Owner:** —

**Where:** `codes/frontend/src/pages/Poll.tsx` (855 lines).

**Summary:** Pure refactor — no behavior change. Target: page file ≤ 200 LOC, no module-level state, each child component < 150 LOC. Extract: `IdentityCard`, `VoteCard`, `ResultsBars`, `AdminPanel`, `PrivacyReceipt`, `StateProgress`. Hooks: `useGroupSync`, `useAnonVote`. Helpers: `lib/friendlyError.ts`, `lib/optionColors.ts`. Both share with P2-14 — coordinate.

### P2-14 — Split `BlindPoll.tsx` (710 LOC) into composed components + hooks {#p2-14}

**Priority:** P2 — **Status:** Open — **Owner:** —

**Where:** `codes/frontend/src/pages/BlindPoll.tsx` (710 lines).

**Summary:** Same shape as P2-13. Extract: `RegisterCard`, `CommitCard`, `RevealCard`, `Countdown`, `ResultsBars` (shared with P2-13), `AdminPanel`, `StateProgress`. Hook: `useBlindVote`. Same `lib/friendlyError.ts` and `lib/optionColors.ts`.

---

## P3 — DX & CI

### P3-15 — Add `solhint` + `prettier-plugin-solidity` {#p3-15}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Summary:** Contract-side linting + formatting. Add `lint` and `format` scripts to `codes/contracts/package.json`. Standard config; pre-baked rule sets work.

### P3-16 — GitHub Actions CI {#p3-16}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Summary:** `.github/workflows/ci.yml`: matrix on `codes/contracts` and `codes/frontend`, runs `npm ci && npm test && npm run lint`. Required check on `main`. Cache `~/.npm` per package.

### P3-17 — Untrack `accounts.txt`, `hardhat-node.log` {#p3-17}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Summary:** `git rm --cached codes/contracts/accounts.txt codes/contracts/hardhat-node.log`, append to `.gitignore` under `codes/contracts/` (or root `.gitignore`).

### P3-18 — Remove committed binaries {#p3-18}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Summary:** `git rm codes/web3-demo.zip codes/system-description.pdf codes/system-description.txt`. They're snapshot artifacts — keep the live source, drop the frozen blobs.

### P3-19 — Loud banner on Mock-verifier deploy + real-verifier variant {#p3-19}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Summary:** Two changes:
1. `scripts/deploy.ts` — when wiring `MockSemaphoreVerifier`, log a multi-line warning so future-you doesn't get fooled into thinking ZK proofs are being verified.
2. New `scripts/deploy-real.ts` (or environment variable in the existing script) that wires the real `SemaphoreVerifier`. Add `npm run deploy:real-verifier`. Document SNARK artifact requirement.

### P1-13 — `registerVoters` batch cap of 100 exceeds mainnet block gas {#p1-13}

**Priority:** P1 — **Status:** Open — **Owner:** —

**Where:** `codes/contracts/contracts/ZkAnonVoting.sol` — the `registerVoters` cap introduced in P1-12.

**Observed:** A7 empirically measured gas during the P1-12 implementation:
- 25-element batch: ~3.8M gas
- 50-element batch: ~24.5M gas (estimateGas)
- 100-element batch: ~50M gas

Mainnet block gas limit: 30M. Hardhat's default per-tx cap: 16.7M. **A 100-element batch fits in neither.** The P1-12 cap of 100 is therefore unreachable in practice — an honest owner who tries to register 100 commitments in one call gets a transaction-too-big revert. The cap as a *security control* (preventing accidental OOM by a careless owner) still works, but the value is not a useful operating bound.

**Why it matters:** A frontend that chunks at 100 (the documented cap) hits gas limits before the cap fires. Users see opaque transaction failures.

**Fix — pick one:**

**Option A:** Lower the cap to a value that fits a single mainnet block. ~50 (`~24.5M gas`) is the highest n that fits 30M comfortably. Recommend 50.

**Option B:** Lower further to ~25 to also fit Hardhat's default tx cap (testability). Cheaper but more frontend chunking.

**Option C:** Make the cap a configurable parameter set at `initialize` time, defaulting to 50. Lets each poll tune to its target chain's block gas limit.

**Acceptance:**
- New cap value documented in code comment + `architecture/module-m1-anon-voting.md` Known Limitations.
- Test boundary updated (existing P1-12 tests use 25 for the success-case, 101 for revert; refactor to use the new cap value -1 for success and cap+1 for revert).
- Frontend should also be updated to chunk at the new value (separate finding if frontend doesn't currently chunk).

**Notes:**
- Gas costs scale roughly linearly with batch size due to `addMember` Merkle insertion cost dominating the loop. Different Semaphore depths or Poseidon implementations could shift the breakpoint.
- Discovered during Sprint 2 P1-12 implementation; the original P1-12 spec claimed "100 fits comfortably under 30M" — that claim was wrong. Lesson: gas claims in spec docs should be empirically verified before they're load-bearing.

---

### P3-20 — Parallel agents need git worktree isolation {#p3-20}

**Priority:** P3 — **Status:** Open — **Owner:** —

**Where:** Orchestrator dispatch flow (no specific file — process change).

**Observed:** Sprint 1 dispatched three implementer agents in parallel (background mode) sharing a single working directory. They raced on `git checkout` operations. Concrete damage observed:
- Agent A2's first commit `feff735 test(contracts): add ZkAirdrop test suite` landed on A1's branch `imp/P0-1-P0-2-poll-page-state-fixes` instead of A2's intended `imp/P0-3-airdrop-tests`. Recovery: `git rebase --onto 5bdc1e0 feff735 imp/P0-1-P0-2-poll-page-state-fixes` to drop the rogue commit, then A2 cherry-picked the same content onto its correct branch (final clean commit `4673bf9`).
- Agent A3 stashed A1's WIP edits to `Poll.tsx` when it switched branches. Stash entry "P0-1-P0-2 wip before P0-3" later dropped as race-residue.
- All three agents reported confusion about "the orchestrator changed HEAD out from under me" — they were observing each other's `git checkout` calls.

**Why it matters:** Race-condition cleanup is manual and risky. A `git rebase --onto` on the wrong branch loses commits silently. As sprints scale (P1 has 8 items, P4 has 5), the chance of a destructive race compounds.

**Fix:** Use the `isolation: "worktree"` option on the Agent tool when dispatching parallel implementer agents. Each agent gets its own git worktree (separate working directory, shared `.git/`), so per-agent `git checkout` operations don't race. Branches are still mergeable back into `main` from the lead worktree.

**Acceptance:**
- Future Sprint dispatches that fire ≥2 implementer agents in parallel use `isolation: "worktree"`.
- Document the orchestrator pattern in `docs/improvements/README.md` (or a new `docs/project/ORCHESTRATION.md` if the section grows): "for parallel dispatch ≥2 agents, always use worktree isolation".
- One serial sprint (after this fix lands) verifies no race-residue stashes appear.

**Notes:**
- Single-agent dispatch (e.g. one implementer fixing one item) does NOT need worktree isolation — overhead not worth it.
- Worktrees may interact awkwardly with the `codes/` reorganization that's still in working tree. Test on a clean repo first.

---

## P4 — Production readiness

### P4-20 — Document module immutability {#p4-20}

**Priority:** P4 — **Status:** Open — **Owner:** —

**Summary:** Add an "Upgrades" section to `docs/architecture/system-overview.md`. Clones are EIP-1167 minimal proxies — non-upgradeable by design. "Upgrade" = new poll. Registry's `registerModule` swap doesn't migrate existing polls.

### P4-21 — Pagination for `getAllPolls` {#p4-21}

**Priority:** P4 — **Status:** Open — **Owner:** —

**Summary:** Add `getPolls(uint256 offset, uint256 limit) returns (PollInfo[])` view to `PollRegistry`. Frontend hook reads in pages of 50. Existing `getAllPolls` deprecated but kept for now (don't break consumers).

### P4-22 — Event-driven poll list {#p4-22}

**Priority:** P4 — **Status:** Open — **Owner:** —

**Summary:** Replace 5-second polling of `getAllPolls` with: initial `getLogs` for `PollCreated` events, then `useWatchContractEvent` for incremental updates. Removes the per-page bandwidth cost as the registry grows.

### P4-23 — Real Groth16 verifier path in nightly CI {#p4-23}

**Priority:** P4 — **Status:** Open — **Owner:** —

**Summary:** Add `test/integration/RealVerifier.test.ts`. Deploy real `SemaphoreVerifier`, fetch SNARK artifacts in CI, generate a real proof, assert the contract verifies it. Slow (~30s) — run nightly only. Depends on P3-19.

### P4-24 — SNARK artifact bundling {#p4-24}

**Priority:** P4 — **Status:** Open — **Owner:** —

**Summary:** Frontend currently fetches SNARK artifacts from `snark-artifacts.pse.dev` at runtime. For production, bundle them in the dApp build (or serve from our own CDN). Document where they came from + their hash.

---

## How to add a new finding

1. Append a new entry at the end of the appropriate priority section.
2. Pick the next ID in that section (e.g., the next P0 after P0-4 is P0-5; the next P1 after P1-12 is P1-13). Don't reuse IDs.
3. Add a one-line row to the status board in `README.md`.
4. Add a one-line entry to the discovery log in `README.md`.
5. Commit as part of whatever PR uncovered the finding (or as a standalone `docs(improvements):` commit if it's not tied to other work).
