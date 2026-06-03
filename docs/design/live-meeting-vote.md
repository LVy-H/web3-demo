# Live Meeting Vote — Design Document

**Status:** SHIPPED — historical design record (do not treat as current state).
**Authors:** [Hoang] + Claude.
**Date:** 2026-05-14.

> This is the original design. The live-meeting flow **shipped** in the Tessera
> Flutter client (`codes/mobile/`) — host dashboard + voter flow + rotating
> signed-ticket QR + face-to-face confirm. Any `codes/frontend/…` (React) paths
> below describe the original plan, not the implementation; see
> [`docs/architecture/system-overview.md`](../architecture/system-overview.md)
> and [`INSTRUCTIONS.md`](../../INSTRUCTIONS.md) for how it actually works today.

---

## TL;DR

Reframe the existing ZK-voting app as a **live in-person meeting voting tool**. Voters scan a rotating QR projected by the organizer, generate an ephemeral identity in their browser (no MetaMask, no login), and the **organizer visually confirms each voter face-to-face by reading a code off the voter's phone screen** before the vote is enabled. This combines a *cryptographic* layer (ZK nullifiers, signed tickets, gasless relay) with a *human social-trust* layer (face-to-face check) — defeating the "share my QR with my friend who isn't here" attack that pure-cryptographic schemes can't fully solve without expensive hardware (Bluetooth beacons, NFC, biometrics).

The cryptographic layer makes cheating *technically expensive*; the human layer makes cheating *socially impossible* in a face-to-face meeting.

---

## 1. Use case

A teacher / facilitator / chair runs a live meeting (classroom, town hall, board meeting, conference session) and wants to take a vote. They need:

- **Low organizer friction**: create a poll in <30 seconds, no contract knowledge required
- **Low voter friction**: scan a QR, tap an option, done. **No wallet, no login, no PII collection**
- **Strong eligibility**: only attendees physically present can vote, exactly once each
- **Privacy**: nobody sees how anyone voted (not the organizer, not other voters, not anyone reading the chain)
- **Auditability**: anyone can verify after the fact that the tally is correct, without de-anonymizing voters

**Non-goals**:
- Async / week-long DAO governance (existing flow already handles this; that's the "non-meeting" mode)
- Anti-coercion ("vote-buying" — receipt-free voting). The receipt feature already shipped is *participation-only*; vote direction is not provable, satisfying anti-coercion within Semaphore's model.

---

## 2. Attack model

| # | Attack | Mitigation |
|---|---|---|
| **A1** | Same voter votes more than once | Semaphore nullifier: each identity can vote at most once per poll. (already shipped) |
| **A2** | Non-attendee learns the poll URL and votes | (a) Poll requires a signed ticket from the organizer to register; (b) tickets expire in 30s; (c) **organizer face-to-face visual confirmation** before the vote is enabled. |
| **A3** | Voter A shares their QR/ticket with non-attendee B | (a) Ticket expires in 30s, so sharing window is tiny; (b) **face-to-face confirmation step** — organizer wouldn't see B at the meeting, so B can't get the green light. |
| **A4** | Voter takes a photo of the projector and sends it to a non-attendee | Same as A3: 30s expiry + face-to-face check. |
| **A5** | Multiple-device voter (one person with phone + tablet) | Face-to-face check + organizer-controlled per-voter confirmation: organizer only confirms one device per person they recognize. |
| **A6** | Replayed network payload (capture POST, replay it) | Each ticket is single-use, tracked by the relayer. |
| **A7** | Forged ticket (random scammer claims they have a ticket) | Ticket signed by organizer's per-poll ephemeral keypair; voter page verifies signature before using it. |
| **A8** | Compromised relayer rejects valid voters / accepts invalid | Relayer signs commitments to consumed-ticket set; voters and observers can audit. (Phase B) |
| **A9** | Vote buying / coercion ("show me your vote receipt for $5") | Receipt proves participation only, not direction. Already shipped. |

**Key insight**: A3 and A4 — the QR-resharing attacks — *can't be solved by cryptography alone* without proof-of-physical-presence hardware. The face-to-face human check is what makes them practically impossible at the cost of <2 seconds per voter.

---

## 3. The three-layer design

### Layer 1 — Cryptographic (machine-checkable)

```
Organizer device                  Voter phone                   Relayer / Chain
─────────────────                 ───────────────                ──────────────
[Generate per-poll                                              
 ephemeral keypair]                                             
       │                                                        
       ▼                                                        
[Project rotating QR]                                           
   {pollId, nonce,                                              
    expires_in_30s,                                             
    org_signature}                                              
       │                                                        
       │  scan                                                  
       └──────────────►  [Verify org signature]                 
                          [Generate fresh                       
                           Semaphore identity]                  
                          [Display 4-digit                      
                           confirmation code]                   
                                                                
   ── Layer 2 (face-to-face check) ──                            
                                                                
                          [User shows code                      
                           to organizer]                        
       ▲                                                        
       └──────────────►  organizer reads code from              
                          their device, checks against          
                          their own dashboard                   
       │                                                        
       ▼                                                        
[Click "Confirm voter"]                                         
   POST /tickets/redeem ───────────────────────────────────►  [Mark ticket consumed]
                                                              [Register identity in poll]
                          ◄────────────────────────────── [Return: vote enabled]
                                                                
                          [Show poll question + options]        
                          [Voter taps option]                   
                          [POST vote ──────────────────►   [Verify ZK proof]
                                                          [Spend nullifier]
                                                          [Tally + emit VoteCast]
                          ◄────────────────────────────── ✓
                          [Show receipt modal — already shipped]
```

### Layer 2 — Social (human-checkable)

The voter's phone displays a short, easily-spoken confirmation code (e.g., 4 digits, or 2 emoji). The organizer projects their dashboard which shows the *current* set of unconfirmed voters and their codes. They scan the room, find the person holding the phone with that code, and click "confirm" next to it.

The organizer cannot be tricked because they're physically looking at the person. A non-attendee can scan the QR but can never have their code read out by the organizer because they aren't in the room.

This is the same human-loop pattern used by:
- Bluetooth pairing ("does code 4729 match on both devices?")
- Bank 2FA call-backs ("did you just authorize a £500 transfer?")
- COVID vaccine passport visual checks (gate agent looks at QR + passport)

### Layer 3 — Hardware proximity (machine-checkable, optional, Phase E)

When the voter's device supports Web Bluetooth (Chrome / Edge on desktop + Android), the voter page automatically scans for the organizer's BLE beacon (a known UUID broadcast from the org's laptop or phone). If detected with strong RSSI (≈ same room, ≤10 m), `proximityVerified = true` is sent to the relayer alongside the registration. The org dashboard shows a green BLE badge on those rows so the org can confirm with a single tap (no need to scan the room for the code).

This is **strictly an augment to Layer 2**, never a replacement: iOS Safari does not support Web Bluetooth, so face-to-face confirmation must remain the baseline.

For an even stronger physical check, **NFC tap** can replace the BLE scan in Android-only deployments (range = 4 cm, "must touch the tag"). See Phase E.2.

---

## 4. UX flows

### 4.1 Organizer UX (timed end-to-end: ~60s to bootstrap)

1. Land on `/` → click `Create Poll`
2. Pick a template (e.g., `Quick yes/no`, already shipped in T1.4) → fill 1 field
3. Toggle `Live Meeting Mode` (NEW) → set voting window (default 10 min)
4. Click `Deploy poll on-chain` (existing, gasless via relayer)
5. Browser auto-redirects to `/live/<pollId>/host`
6. Host page (projector-friendly):
   - **Big rotating QR** in the centre (refreshes every 25s)
   - **Pending voters list** on the right: each row shows `[CODE 4729]  [Confirm ✓]  [Reject ✗]`
   - **Live tally** below: bar chart updates as confirmed votes land
   - **Time remaining** counter
7. Voters trickle in, scan QR, show their code; organizer confirms each one face-to-face
8. When time elapses or organizer clicks `End vote`, results freeze and final bars + percentages are shown

### 4.2 Voter UX (timed end-to-end: ~10s per voter)

1. Voter pulls out phone, opens camera, scans the projected QR
2. Browser opens `/live/<pollId>/vote?t=<ticket>`
3. Page shows: **`Show this code to the organizer: 4-7-2-9`** in giant text
4. Voter holds phone up; organizer reads `4729` and clicks confirm on their dashboard
5. Voter's screen transitions to: poll question + N option buttons
6. Voter taps an option → ZK proof generates client-side (~5-10s) → relayed → vote cast
7. Receipt modal appears (already shipped) with QR for downstream verification

### 4.3 Verifier UX (post-meeting, anyone)

Already shipped:
- Anyone with a receipt JSON / QR can open `/verify` to confirm participation on-chain
- Tally results are public on-chain via `VoteCast` events; `/poll/:address` shows aggregated bars

---

## 5. Architecture

### 5.1 New routes

| Route | Who | What |
|---|---|---|
| `/live/:pollId/host` | Organizer | Projector page: rotating QR, pending-voter dashboard, live tally |
| `/live/:pollId/vote?t=<ticket>` | Voter | Ephemeral-identity bootstrap, confirmation-code display, vote submission |
| `/verify?...` | Anyone | (already shipped) — receipt verification |

### 5.2 New backend (relayer additions)

| Endpoint | Body | Purpose |
|---|---|---|
| `POST /tickets/issue` | `{pollId}` | Organizer-only. Mints a fresh signed ticket. (Could be done client-side too — server only adds rate-limiting.) |
| `POST /tickets/pending` | `{pollId, ticket, ephemeralIdentityCommitment, confirmationCode}` | Voter announces "I want to vote, my code is X." Adds to pending-voter queue. |
| `GET /tickets/queue?pollId=X` | (org-key auth) | Organizer dashboard polls this for pending voters. |
| `POST /tickets/redeem` | `{pollId, ticket, signedByOrganizer}` | Organizer confirms a voter. Marks ticket consumed, returns the relayer's blessing for the registration tx. |
| `POST /relay/register` | (existing pattern, scoped to redeemed tickets) | Relays the on-chain `registerVoter(commitment)` call. |
| `POST /relay/vote` | (existing) | Relays the actual `castVote(...)` call. |

### 5.3 Cryptographic primitives

- **Per-poll organizer keypair**: ed25519 (or simpler: secp256k1 from a generated wallet). Generated client-side at poll-creation time, stored in `localStorage` keyed by pollId. Public key embedded in poll metadata or stored on-chain.
- **Ticket format** (compact, fits in QR):
  ```
  base64url({
    p: pollId,        // 20 bytes hex
    n: nonce,         // 8 bytes random
    e: expiresAt,     // 4 bytes unix-seconds
    s: ed25519_sig    // 64 bytes
  })
  ```
- **Confirmation code**: SHA-256(`ticket-nonce` || `ephemeral-identity-commitment`) → first 16 bits → 4-digit decimal. Deterministic from the voter's first registration attempt; can't be brute-forced because the verifier has the *same* values.
- **Ephemeral Semaphore identity**: generated fresh in voter's browser, NEVER persisted to a wallet. Lives only for the duration of this poll. After voting, it's discarded.

### 5.4 Data flow

```
Poll deploy ──► smart contract emits PollCreated
                     │
                     ▼
             Organizer host page
             • generates ephemeral keypair
             • mints rolling tickets
             • shows queue from relayer

Voter scan ──► /live/:pollId/vote?t=<ticket>
                     │
                     ▼
             Voter page
             • verifies ticket sig (org pubkey from poll meta)
             • generates fresh Semaphore identity
             • computes confirmationCode = hash(ticket.nonce || identity.commitment).first(4 digits)
             • POST /tickets/pending → queues itself with org

Org confirm ─► POST /tickets/redeem
                     │
                     ▼
             Relayer
             • marks ticket consumed
             • verifies org's signature on the redeem
             • signs the registration tx
             • POSTs to chain → on-chain Semaphore group adds commitment

Voter votes ─► generates ZK proof, POST /relay/vote
                     │
                     ▼
             Relayer + chain (existing path) → tally updated, receipt issued
```

---

## 6. Cryptographic guarantees

| Guarantee | Mechanism |
|---|---|
| **Single vote per identity** | Semaphore nullifier — already enforced on-chain (`isNullifierUsed[n]`) |
| **Single registration per ticket** | Relayer state (`consumedTickets: Set<nonce>`); could be on-chained if relayer trust is unacceptable |
| **Ticket integrity** | ed25519 signature by organizer's per-poll keypair; verified client-side AND server-side |
| **Ticket time-bound** | Embedded `expiresAt`; rejected if `now > expiresAt` |
| **Voter privacy from organizer** | Organizer only sees `(confirmationCode, ephemeralCommitment)` pairs in the pending queue. They never see the vote choice. The ZK proof on-chain doesn't reveal which commitment cast the vote. |
| **Voter privacy from chain observers** | Same as above. Standard Semaphore privacy. |
| **Auditability of tally** | All votes on-chain; `VoteCast` events publicly tally-able. |
| **Auditability of voter-set integrity** | Relayer signs commitment to consumed-ticket-set per poll. Anyone can verify the set is consistent. (Phase B) |
| **Receipt-freeness for direction** | Receipt JSON / QR exposes participation but NOT vote direction. Already shipped. |
| **Non-receipt-freeness for participation** | The voter CAN prove "I voted in this poll" if asked. Acceptable in the meeting context (you're publicly attending). |
| **Physical-proximity attestation (optional)** | Phase E: voter's device scans organizer's BLE beacon UUID; RSSI > -75 dBm marks `proximityVerified` true on the registration. Hardware-checkable, augments the human face-to-face check. iOS gracefully falls back to Layer 2. |

---

## 7. Phased implementation roadmap

### Phase A — MVP (~1 day, this session if you OK)

- [ ] `/live/:pollId/host` page: rotating QR (refresh every 25s), pending-voter list (mock — read from in-memory or relayer endpoint), live tally (subscribe to `VoteCast`)
- [ ] `/live/:pollId/vote?t=<ticket>` page: parse + verify ticket, generate ephemeral Semaphore identity, display 4-digit code, polling for "confirmed" state
- [ ] Relayer additions: `POST /tickets/pending`, `GET /tickets/queue`, `POST /tickets/redeem`, plus the consumed-tickets Set
- [ ] CreatePoll: add **Live Meeting Mode** toggle that branches the deploy → redirects to `/live/.../host` instead of `/poll/...`
- [ ] Smoke test the full loop with two browsers (one as organizer, one as voter)

### Phase B — Hardening (~1 day, follow-up)

- [ ] Relayer signs commitments to consumed-ticket-set; expose `/tickets/manifest` for audit
- [ ] Per-poll organizer keypair: persist to localStorage with poll ID; UI to "regenerate" if compromised
- [ ] Time-bounded poll auto-close (currently polls don't have end-time; needs contract change OR off-chain enforcement via the host page)
- [ ] PWA install for voter page so it works offline / installs to home screen
- [ ] Projector-mode CSS for host page (huge text, dark, low-distraction)

### Phase C — Polish (~1 day, optional)

- [ ] **Multiple QRs in parallel** for big crowds (e.g., 4 QRs on 4 corners of the screen, different ticket batches)
- [ ] **Org-side bulk confirm** ("approve all current 5 voters in queue at once")
- [ ] **Voter receipt enhancements** ("download as image you can post on social")
- [ ] **i18n** (English, Vietnamese — testimonial: "khúc nhập bị nhân đôi" already in test names)
- [ ] **Telemetry** (anonymous: how many polls, how many voters, average time-to-vote)

### Phase D — Polish (~1 day, optional)

(See section 7 above — items moved up; renumbering this section so Phase E is the BLE/NFC layer.)

### Phase E — Hardware-assisted physical-presence (optional, ~1-2 days)

Augment the face-to-face check (Layer 2) with **automated proof of physical proximity** via Web Bluetooth or Web NFC. The face-to-face check stays as the fallback for devices/browsers that don't support these APIs.

**Three deployment models:**

#### E.1 — BLE beacon (Web Bluetooth scan, voter-side)

Organizer runs a small "beacon" on their laptop/phone (any Web Bluetooth-capable device with a known UUID). The voter's browser, when on the `/live/.../vote` page, asks for permission and scans for that UUID. If the beacon is detected with RSSI strong enough to indicate ≤10m distance, an additional `proximityProof` field is added to the registration. Otherwise, the voter falls back to the face-to-face flow.

| Pro | Con |
|---|---|
| Automatic, sub-second proximity check | Web Bluetooth not supported on iOS Safari (or iOS Chrome — they share WebKit) |
| Works in big rooms where face-to-face is slow | Requires user to tap "allow Bluetooth" — extra friction |
| RSSI is fakeable but only by an attacker physically near the room | Beacon device must be running for the duration |

**Browser support** (as of May 2026): Chrome / Edge / Opera on desktop + Android. Firefox: behind a flag. **iOS: not supported.**

#### E.2 — NFC tap (Web NFC, voter-side)

Organizer has an NFC tag (cheap, <$1 each — or just a phone in NFC mode). Voter taps phone to the tag to confirm presence. Tag emits a short-lived signed token that the voter's page reads + sends to the relayer.

| Pro | Con |
|---|---|
| Unambiguous: NFC range is ~4 cm, *literally* requires touch | Web NFC is Chrome-on-Android only (no desktop, no iOS) |
| One physical token (the tag) lasts forever | Forces a physical bottleneck — single tag, queue forms |
| Stronger anti-collusion than BLE | Cheaper alternative: organizer just shows the QR on a phone (already covered in main design) |

**Browser support**: Chrome on Android only. Not iOS, not desktop, not Firefox.

#### E.3 — Hybrid: BLE-as-bonus, face-to-face-as-baseline

The recommended Phase E approach: implement BLE detection as an **augment**, not a replacement. The voter's confirmation code is the primary signal; if BLE is also available AND the proximity check passes, the org dashboard shows a green ✓✓ instead of just ✓ (so the org knows they don't need to look as hard for the voter — the device confirms it's in the room).

**Sample flow with E.3:**

```
Voter scans QR → vote page loads
  │
  ├─ if Web Bluetooth supported AND user allows:
  │    scan for org beacon UUID
  │    → if RSSI > -75 dBm (≈ same room): proximityVerified = true
  │
  └─ ALWAYS: display 4-digit confirmation code

Org dashboard:
  • voter row shows code "4729" + (if proximityVerified) a green BLE icon
  • org can either trust the BLE auto-confirm + click confirm with one tap
  • OR ignore the BLE signal and still do the face-to-face check
```

This way iOS users still work (no BLE, manual face-to-face); Android users get a faster confirmation; the cryptographic layer is unchanged.

#### E.4 — What this DOES NOT solve

- **Same-room collusion**: someone in the room can BLE-pair on behalf of someone outside via a TCP-tunneled BLE relay. (Real attack class — "BLE relay attacks" — but extremely rare for this use case.)
- **Vote-buying inside the room**: Layer 2 (face-to-face) and Layer 3 (BLE) only verify presence. They don't prevent in-room coercion. Receipt-freeness for direction (already shipped) handles that.

#### E.5 — Implementation effort

- Web Bluetooth API helper: `navigator.bluetooth.requestDevice({filters: [{services: [ORG_BEACON_UUID]}]})` — ~30 lines.
- Beacon side (organizer): on Linux/macOS use `bleno` (Node.js) or a simple BLE-broadcast tool. On Android, the org's phone can use Eddystone-UID broadcast.
- ~1 day of work + testing on multiple devices.

### Phase F — Out of scope for this project (acknowledge)

- Cross-chain deployment
- Token-gated polls (different use case; covered by snapshot.org)
- Multi-question polls (separate feature in queue as task #12)
- iOS BLE/NFC (Apple platform constraints — out of our control)

---

## 8. Trade-offs & honest limitations

| Trade-off | Reasoning |
|---|---|
| **Trusted organizer** | The face-to-face check assumes the organizer is honest — they could "confirm" a non-attendee they're colluding with. *Mitigation*: in a real meeting, multiple attendees see the queue projected on the screen; collusion is socially detectable. |
| **Trusted relayer** | Relayer enforces single-use tickets. If it lies, attacker wins. *Mitigation*: Phase B adds signed manifest of consumed tickets so anyone can audit. |
| **Voter must have a smartphone** | True; same as Mentimeter / Slido. Acceptable for the target use case. |
| **Voter device needs JS + camera** | Yes. No fallback for older devices in this design. |
| **Cellular dead spot at venue** | If voter's phone has no internet, they can't relay. *Mitigation*: poll could be deployed to an L2 with cheaper gas + voter pays gas with a pre-funded ephemeral wallet (heavy). For MVP, assume connectivity. |
| **Organizer-key compromise** | If the per-poll organizer key leaks, attacker can mint valid tickets. *Mitigation*: ephemeral key per poll; key never leaves the organizer's device; even if compromised, attack scope is one poll. |
| **Photo-of-projector attack** | Someone in the room could photograph the projector and send the QR to a non-attendee, who then scans within 25s. The non-attendee STILL needs to pass face-to-face confirmation, so the attack fails at Layer 2. |
| **Same-person two-phones attack** | Voter has phone + tablet, registers both. Distinct ephemeral identities → distinct nullifiers → two votes counted. *Mitigation*: organizer at the face-to-face step would see both devices and only confirm one. The check is "this person, this device" not "this device". |

---

## 9. Open questions for review

1. **Should the organizer keypair be on-chain or off-chain?**
   - On-chain: stored in poll metadata; verifier (anyone) can check tickets without trusting the organizer's announcement of their pubkey.
   - Off-chain: lighter weight; published in a poll-side metadata blob.
   - **Recommendation**: on-chain (one extra `bytes32` field on the poll struct). Worth the tiny gas cost.

2. **What's the ticket expiry sweet spot?**
   - Too short (5s): voters who hesitate miss it.
   - Too long (5 min): A3/A4 attack window large.
   - **Recommendation**: 25-30 seconds. Long enough for a slow scanner, short enough that resharing is impractical.

3. **Should we allow re-issue of the confirmation code?**
   - If the voter's screen times out / locks before showing the code, they need to re-scan a fresh QR.
   - **Recommendation**: yes; voter can tap "Get a fresh code" which generates a new identity (the previous one is discarded, invalid).

4. **Can a single ticket admit multiple voters in a "fast crowd" mode?**
   - Default: no (one ticket = one voter).
   - For huge crowds (e.g. 200+), organizer might want a "burst" mode: one QR is good for the next N voters within 60s, organizer doesn't confirm individually.
   - **Recommendation**: ship without it; add as Phase C if needed. Loses the face-to-face check for that mode.

5. **What does the on-chain `live` flag even change?**
   - Could be a field in the poll's initialize args, OR purely off-chain (just a frontend mode).
   - **Recommendation**: purely off-chain. Polls are polls; "live mode" is an organizer's UI choice. Simpler.

---

## 10. Implementation file map (preview)

```
codes/frontend/src/
├── pages/
│   ├── LiveHost.tsx          NEW    /live/:pollId/host — organizer projector
│   ├── LiveVote.tsx          NEW    /live/:pollId/vote — voter ephemeral
│   └── CreatePoll.tsx        MODIFY add Live Meeting toggle
├── components/live/
│   ├── RotatingQR.tsx        NEW    QR that refreshes every 25s
│   ├── PendingVoterList.tsx  NEW    org-side queue with confirm/reject
│   ├── ConfirmationCode.tsx  NEW    voter-side big code + animation
│   └── LiveTally.tsx         NEW    real-time vote bars (subscribe VoteCast)
├── lib/
│   ├── ticket.ts             NEW    sign / verify / encode / decode tickets
│   ├── confirmationCode.ts   NEW    derive 4-digit code from nonce + commitment
│   └── orgKeypair.ts         NEW    generate / store / load per-poll org key

codes/relayer/src/
├── tickets.ts                NEW    consumed-tickets Set + endpoint handlers
└── index.ts                  MODIFY mount the new endpoints

contracts/
└── (no changes for Phase A)
```

---

## 11. Demo script (for the teacher)

> **Setup** (10 sec): "I'm going to demo a real-time anonymous voting tool. I'm the meeting organizer. Anyone in the audience can be a voter — pull out your phones."
>
> **Create poll** (15 sec): organizer opens dashboard → `Create Poll` → picks `Quick yes/no` template → toggles `Live Meeting` → deploys.
>
> **Open host page** (3 sec): browser auto-redirects to projector view. Big rotating QR appears.
>
> **First voter** (10 sec): "Anyone want to vote? Scan the QR." Audience member scans. Their phone shows a big `4-7-2-9`. They hold up phone. Organizer reads the code, finds the row in the pending queue projected on the screen, clicks confirm. Voter's screen flips to poll question + Yes / No buttons. They tap one. Vote bar updates live on the projector.
>
> **Second voter** (10 sec): same flow, different code, different voter.
>
> **The cheating attempt** (15 sec): "Now let's see what happens if I share my QR with someone NOT in the room." Send screenshot of QR to a friend on Slack. Friend scans on their phone. Friend's screen shows a code (e.g. `1-1-9-3`). But the friend isn't in the room — when I look at the projected queue and see code `1-1-9-3`, I don't see anyone in the room holding it. I click reject. Friend's screen says "rejected." They can never vote.
>
> **Wrap** (10 sec): "Vote ends, results are anonymous, on-chain, verifiable. Each voter has a downloadable receipt that proves they participated but doesn't reveal what they voted for."

Total demo: ~60 seconds. Teacher sees: a real product, a real attack model, a real cryptographic + social-trust solution, working live.

---

## 12. References

- Semaphore protocol — https://semaphore.pse.dev/
- Aragon receipt-freeness — https://blog.aragon.org/private-onchain-voting-on-aragon-with-maci/
- Mentimeter (no eligibility check, baseline competitor) — https://www.mentimeter.com/
- Slido (post-event verification, no anti-replay) — https://www.slido.com/
- Bluetooth Numeric Comparison (the source of the face-to-face pattern) — https://www.bluetooth.com/blog/bluetooth-pairing-part-4/
