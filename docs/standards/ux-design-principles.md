# UX Design Principles & Rules

Learned from building the Anonymous Web3 Voting System. These rules apply to all current and future development on this project.

---

## Core Philosophy

**The user is a student, not a crypto native.** Every design decision must pass this test: "Can someone who has never used MetaMask before complete this flow in under 2 minutes?"

---

## Rule 1: Zero Manual Configuration

**Never ask the user to copy-paste technical values.**

| Bad | Good |
|-----|------|
| "Add network: RPC URL http://127.0.0.1:8545, Chain ID 31337" | Auto-add via `wallet_addEthereumChain` on connect |
| "Copy this contract address and paste it in..." | App reads addresses from config automatically |
| "Import this private key into MetaMask" | Provide a funded test account via embedded wallet (future) |

**Lesson learned:** The original PoC required 9 manual steps. After auto-network-add, it dropped to 3. Every manual step is a dropout point.

---

## Rule 2: One Action = One Click

Each user goal should map to exactly one button press. If an action requires multiple transactions, batch them or hide the intermediate steps.

| Goal | Bad | Good |
|------|-----|------|
| Register + vote | "Submit Commitment" → wait → "Generate Proof" → wait → "Cast Vote" | "Vote" (handles all steps internally with progress indicator) |
| Create a poll | Fill form → deploy → register module → confirm 3 transactions | Fill form → "Create" (single meta-transaction or batched) |
| Verify a receipt | Copy JSON → open verifier page → paste → click verify | "Verify" button on receipt card → inline result |

---

## Rule 3: Progressive Disclosure

Show complexity only when the user asks for it. Default to the simplest view.

**Layer 0 (everyone sees):** Poll title, options, vote button, results
**Layer 1 (click to expand):** ZK proof status, transaction hash, nullifier info
**Layer 2 (developer/admin):** Contract address, ABI, Semaphore group ID, raw events

Never show Layer 1/2 content by default. Use expandable sections, "Advanced" toggles, or separate admin pages.

---

## Rule 4: State Must Be Obvious

The user must always know:
1. **What phase** the poll is in (Registration / Voting / Ended)
2. **What they can do** right now (register, vote, view results, nothing)
3. **What they're waiting for** (admin to start voting, transaction to confirm, proof to generate)

**Implementation:**
- Use colored badges for poll state (yellow = Registration, green = Voting, gray = Ended)
- Disable buttons that can't be used in the current phase (don't hide them -- show them disabled with a tooltip explaining why)
- Show a progress bar or spinner during long operations (ZK proof generation takes 3-10 seconds)

---

## Rule 5: Errors Must Be Human-Readable

Never show raw Solidity revert strings or transaction hashes as error messages.

| Revert String | User-Facing Message |
|---------------|---------------------|
| `"Not in voting phase"` | "Voting hasn't started yet. Wait for the poll admin to open voting." |
| `"You have already voted"` | "You've already voted in this poll. Each identity can only vote once." |
| `"Invalid option index"` | "Something went wrong with your vote selection. Please try again." |
| `"Initialization failed"` | "Failed to create the poll. Please check your wallet and try again." |
| `execution reverted` | "Transaction failed. Make sure you're connected to the correct network." |

**Implementation:** Wrap all contract calls in try-catch. Map known revert strings to friendly messages. For unknown errors, show a generic message + expandable "Technical details" section.

---

## Rule 6: Feedback Is Immediate

Every user action must produce visible feedback within 200ms, even if the actual operation takes longer.

| Action | Immediate Feedback | After Completion |
|--------|-------------------|-----------------|
| Click "Vote" | Button changes to "Generating proof..." with spinner | "Vote cast!" with confetti or checkmark |
| Click "Create Poll" | Button changes to "Confirm in wallet..." | Redirect to new poll page |
| Paste invite token | Input border turns green, "Identity loaded" | Ready-to-vote state enabled |
| Click "Connect MetaMask" | Button changes to "Connecting..." | Wallet address shown in header |

**Never leave the user staring at an unchanged screen.** If MetaMask is waiting for confirmation, say so.

---

## Rule 7: Invite Links Over Manual Tokens

For M1 (anonymous voting), the admin generates invite tokens. The current flow requires voters to receive a token string and paste it manually.

**Better flow (target):**
1. Admin creates poll → generates invite link: `https://app.com/poll/0x.../join?token=abc123`
2. Admin shares link via chat/email
3. Voter clicks link → identity auto-derived → one click to register → ready to vote

**Until invite links are built:** At minimum, make tokens easy to copy. Show a "Copy" button next to each token. Show "Share via..." options if the Web Share API is available.

---

## Rule 8: Mobile-First Layout

Students use phones. Every page must work on a 375px-wide screen.

- Use single-column layout on mobile, two-column on desktop (already doing this with `grid-cols-1 lg:grid-cols-2`)
- Touch targets must be at least 44x44px
- No hover-only interactions (hover doesn't exist on mobile)
- Test with MetaMask mobile browser

---

## Rule 9: No Blockchain Jargon in Primary UI

| Avoid | Use Instead |
|-------|-------------|
| "Transaction hash" | "Confirmation ID" (in expandable details) |
| "Gas fee" | "Network fee" (or hide entirely if gasless) |
| "Contract address" | "Poll ID" (show address in advanced view) |
| "Nullifier" | "Vote receipt" or "Proof of participation" |
| "Commitment" | "Voter registration" |
| "ZK proof" | "Verifying your identity..." (in progress message) |
| "Semaphore group" | "Voter pool" |
| "Block explorer" | Don't link to it in primary UI |

The blockchain is the backend. Users don't need to know it exists. Save technical terms for developer docs and the "Advanced" panel.

---

## Rule 10: Deterministic Dev Environment

The development environment must be reproducible with zero configuration.

- **Deterministic addresses:** On a fresh Hardhat node, contract addresses are always the same. The deploy script writes them to `deployed-addresses.json`, which the client reads.
- **No external dependencies for local dev:** Everything runs locally. No Cloudflare tunnels, no external RPCs, no testnet faucets needed.
- **One command to start:** `./dev-stack.sh up` (node → deploy → demo poll → relayer) gives you a working system.
- **No wallet needed for testing:** the dev signer (`DEV_PRIVATE_KEY`) and the sponsored relayer let automated tests and demo voters transact without MetaMask.

---

## Checklist: Before Any Frontend PR

- [ ] Does it work on mobile (375px width)?
- [ ] Are all error messages human-readable (no raw revert strings)?
- [ ] Does every button click produce immediate visual feedback?
- [ ] Is blockchain jargon hidden from the primary UI?
- [ ] Are all manual copy-paste steps eliminated or minimized?
- [ ] Is the current poll state obvious at a glance?
- [ ] Does the flow work for someone who has never used MetaMask?
