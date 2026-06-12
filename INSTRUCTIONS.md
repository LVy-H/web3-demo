# Using Tessera — End-user / Demo-runner Guide

What you are going to do: launch the **Tessera** app, browse polls, create a
poll, cast a vote in any of the six voting modules, verify a participation
receipt, and (optionally) run a live in-person meeting with a rotating QR.

Tessera is one Flutter codebase that runs on **mobile, desktop, and web**. There
is no separate browser dApp — this single app is the only client. For developer
setup (start the chain, deploy contracts, run the app), start at
[`codes/README.md`](codes/README.md). For how the system fits together, see
[`docs/architecture/system-overview.md`](docs/architecture/system-overview.md).

> **Voting (proof generation) currently runs on the web build.** Native and
> desktop builds are read-only for voting today — you can browse, verify, and
> (with a dev signer) create and host, but casting a vote needs the in-browser
> prover. The vote panels say so when proving is unavailable. Run
> `flutter run -d chrome` to vote.

---

## Run the app

The full multi-terminal runbook lives in
[`codes/README.md`](codes/README.md#quick-start-local-4-terminals) — start the
Hardhat node, deploy contracts, then launch the app. Don't duplicate it here;
come back once contracts are deployed.

One-step local stack (chain + deploy + a seeded demo poll + relayer):

```bash
./dev-stack.sh up       # ./dev-stack.sh down to stop, status to inspect
```

Then launch the app:

```bash
cd codes/app/apps/tessera
flutter run -d chrome    # web — voting works here
# or: flutter run -d linux        (desktop; read-only voting)
# or: flutter run -d <android-serial>
```

No wallet or MetaMask is required for the default local flow. The app signs with
a **dev signer** (`DEV_PRIVATE_KEY`) or routes through the **sponsored relayer**,
so non-technical demo voters never touch a wallet. (MetaMask / WalletConnect is
only relevant to the optional wallet path on desktop/web.)

---

## The app at a glance

A persistent **bottom navigation bar** has four tabs:

| Tab          | What it does                                                       |
| ------------ | ----------------------------------------------------------------- |
| **POLLS**    | Browse all polls; tap one to open its detail + vote screen.       |
| **VERIFY**   | Confirm a vote was counted from a poll address + nullifier.       |
| **CREATE**   | Deploy a new poll (pick the voting type).                         |
| **IDENTITY** | Manage your Semaphore identity seed (create / import / copy).     |

The top bar shows the **TESSERA** wordmark and a **LOCAL / REMOTE** network chip.
The hamburger **drawer** holds the wallet button, network + relayer hosts, a
link to **Settings**, and an about line.

---

## Browse polls (POLLS tab)

The Polls screen lists every poll the registry knows about as a card grid. Each
card shows the category, a state chip (**VOTING** / **UPCOMING** / **ENDED**),
the title, the short creator address, and the live vote tally.

- **Filter** by status (Active / Upcoming / Ended / All) and category, and
  **search** by title or description, from the strip under the hero.
- **Pull to refresh** (or it reloads on open) to re-read the chain.
- **Tap a card** to open its detail screen. The card passes the on-chain module
  type, so the app opens the right ballot for that poll.

---

## Create a poll (CREATE tab)

1. Pick a **VOTING TYPE**:
   - **Anonymous — single choice** (anon-vote, M1) — the default; pick exactly
     one option.
   - **Approval — multi-select** (approval-vote) — approve any number of options.
   - **Ranked choice** (ranked-vote) — rank up to 8 options; an instant-runoff
     finds the winner.
   - **Quadratic** (quadratic-vote) — spend a 100-credit budget; cost grows as
     votes².
   - **Survey — multiple questions** (survey-vote) — compose several questions
     answered in one ballot.
   - **Blind — commit-reveal** (blind-vote) is shown but **disabled in the app**;
     it needs a reveal window the create form doesn't collect yet, so create
     blind polls from the web app's create flow.
2. Enter a **title** and optional **description**.
3. Add **options** (at least two; ranked/quadratic cap at 8). For a survey, use
   the **question builder** instead (1–16 questions, 2–32 options each).
4. **Deploy.** With the dev signer active, deploy is signed locally and broadcast
   to the configured RPC — no wallet needed. The anonymous type can also deploy
   over a connected wallet; the other types require the dev signer today.

> A phone wallet can only broadcast to a chain it can reach — a public testnet,
> not the host-local Hardhat node. For local demos, use the dev signer (it's on
> by default with `./dev-stack.sh up`).

---

## Vote

Open a poll from the Polls tab. Every poll detail screen shows a **phase strip**
(Registration → Voting → Ended), a **live results** panel, and — during the
Voting phase, on a build with the prover — the ballot for that module. Voting is
anonymous: you prove membership in the poll's Semaphore group with a
zero-knowledge proof, so the chain records *that* a member voted — counting the
choice toward a public aggregate tally — never *who* cast it.

To be eligible you need a **Semaphore identity** (manage it on the IDENTITY tab —
see below) whose commitment has been registered in the poll. The ballot prefills
your saved identity seed; if you're not yet registered, it shows your commitment
to copy and hand to the organizer.

### Anonymous — single choice (M1)

Select one option, confirm the identity seed is filled in, then
**CAST ANONYMOUS VOTE**. The app generates the proof
(*GENERATING PROOF…* → *SUBMITTING…*) and the vote lands; the results panel and
the *VOTES CAST* counter update.

### Blind — commit-reveal (M2)

The blind poll drives a three-phase lifecycle in the **YOUR ACTIONS** panel:
**REGISTER TO VOTE** during Registration, **COMMIT VOTE** (your choice stays
hidden) during Voting, and **REVEAL MY VOTE** after voting ends. The tally is
empty until voters reveal. The poll owner also gets START / END / FINALIZE
controls here. Reveal where you committed — the salt is saved on that device.

### Approval — multi-select

Tick any number of options, then **CAST APPROVAL BALLOT (n)**. The tally counts
every approval.

### Ranked choice

Tap options to add them to your ranking, **drag to reorder** (1 = top choice),
remove any you change your mind on, then **CAST RANKED BALLOT (n)**. The winner
is decided by an instant-runoff computed off-chain.

### Quadratic

Use the **+ / −** steppers to spend your 100 credits across options. The budget
meter shows **CREDITS SPENT / 100** and casting *v* votes for one option costs
*v²* credits. When you're done, **CAST QUADRATIC BALLOT (n)**.

### Survey — multiple questions

Answer each question (single-choice picks one; multi-select checks any that
apply), then **CAST SURVEY BALLOT** — one anonymous ballot binds your whole
answer vector.

> **Gasless / wallet-free voting.** You still generate the proof on your device;
> the optional relayer signs and submits it for you, so you never hold ETH. The
> relayer can't see your identity or change your vote (the option/answers are
> bound into the proof) — it can only refuse to forward. See
> [`codes/relayer/README.md`](codes/relayer/README.md).

---

## Verify a receipt (VERIFY tab)

Anyone can confirm a vote was counted without learning who voted or which option
they chose. Paste the **poll address** and the **nullifier**, then
**VERIFY RECEIPT**:

- **VOTE VERIFIED** — the nullifier is on-chain; the vote was counted (the option
  stays hidden).
- **NOT FOUND** — no vote with that nullifier in that poll.

Verify also accepts a deep link (`/verify?poll=…&nullifier=…`) that prefills both
fields and checks automatically.

---

## Identity (IDENTITY tab)

Your Semaphore **seed** is the one secret you need to vote anonymously across
polls. On this screen you can **create a new identity**, **import** an existing
seed or organizer invite token, **reveal / copy** the seed, or **clear** it. When
a prover is available the screen also derives your **commitment** — copy it and
hand it to an organizer to be registered in their poll. The seed never leaves the
device unless you explicitly copy it; anyone holding it can vote as you, so keep
it secret.

---

## Live in-person meeting

Tessera can run a face-to-face meeting where the organizer admits voters in real
time with a rotating QR — no wallets, no pre-shared identities.

### Host a session

From a poll you own that's still in **Registration**, the detail screen shows
**ORGANIZE LIVE SESSION →**. That opens the host dashboard:

- A **QR** that rotates every 25 seconds (a signed ticket) for voters to scan.
- A **PENDING QUEUE** of voters who've joined, each showing a **4-digit code**.
- Hosting needs the dev signer (or owner wallet); without it the screen is
  read-only.

When a voter shows you their code in person, tap **CONFIRM** on their row — that
registers their ephemeral commitment on-chain. Use **START VOTING** / **END
VOTING** to drive the phase.

### Join as a voter

Open the live vote screen (the QR deep-links straight to it). **Scan** the
organizer's QR (camera on mobile) or **paste** the ticket link, then **JOIN**.
The app mints an **ephemeral identity** and shows you a large **4-digit code** —
show it to the organizer. Once they confirm you face-to-face, voting unlocks
automatically: pick an option and **CAST ANONYMOUS VOTE**. (As elsewhere, casting
needs the prover, so run the web build.)

---

## Settings & diagnostics

The drawer's **Settings** screen is read-only diagnostics: the chain ID, RPC and
relayer hosts, the registry address, how the app **signs** (dev signer vs.
wallet) and **proves** (web / desktop sidecar / read-only), a shortcut to manage
your identity, and the app version.

---

## What's next

- **Architecture deep dive** —
  [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
  plus the per-module files
  ([m1-anon](docs/architecture/module-m1-anon-voting.md),
  [m2-blind](docs/architecture/module-m2-blind-voting.md),
  [approval](docs/architecture/module-approval.md),
  [ranked](docs/architecture/module-ranked.md),
  [quadratic](docs/architecture/module-quadratic.md),
  [survey](docs/architecture/module-survey.md),
  [airdrop](docs/architecture/module-airdrop.md)).
- **Developer setup & the local stack** — [`codes/README.md`](codes/README.md).
- **Gasless relay & sponsored lifecycle** —
  [`codes/relayer/README.md`](codes/relayer/README.md).
- **Backlog and known gaps** —
  [`docs/improvements/findings.md`](docs/improvements/findings.md)
  (`P4-23` / `P4-24` track wiring the real Groth16 verifier for public
  networks).
