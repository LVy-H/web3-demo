# Voting Module Comparison

## Which module should I use?

### "I want voters to be completely anonymous"
Use **M1: Anonymous Token Voting**.
- Nobody (not even the admin) can link a vote to a person.
- Voters prove membership via ZK proof.
- Live tally visible, but individual votes untraceable.
- Trade-off: Requires invite token distribution. Cannot track who participated (by design).

### "I need to know who voted but not what they voted"
Use **M2a: Blind Voting (Live Tally)** or **M2b: Blind Voting (Sealed)**.
- Voter addresses recorded on-chain. Admin can see participation.
- Vote content is encrypted or committed -- individual choices hidden.
- M2a shows running aggregate tally. M2b hides everything until reveal trigger.
- Trade-off: Voters are not anonymous. Their participation is public.

### "I want results hidden until enough people vote"
Use **M2b: Blind Voting (Sealed)** with a threshold trigger.
- No results visible during voting phase.
- Results revealed only after N votes received or deadline passes.
- Prevents bandwagon effects and strategic voting.
- Trade-off: Voters must return to reveal (commit-reveal). Non-revealers lose their vote.

### "I need proof that someone voted"
Add **M3: Participation Receipt** to any module.
- For M1: ZK proof of participation (anonymous receipt).
- For M2: Signed attestation + on-chain event verification.
- Off-chain receipt format: JSON file the voter can share.
- Verifiable by anyone via the contract's `verifyParticipation()` method.

## Feature Matrix

| Feature | M1 (Anon) | M2a (Blind Live) | M2b (Blind Sealed) |
|---------|-----------|-------------------|---------------------|
| Voter anonymity | Yes | No | No |
| Vote content hidden | Yes (aggregate only) | Yes (aggregate only) | Yes (until reveal) |
| Live tally | Yes | Yes | No |
| Participation tracking | No | Yes | Yes |
| Participation receipt | ZK proof | Signed attestation | Signed attestation |
| Sybil resistance | Token-gated | Address-gated | Address-gated |
| Crypto primitives | Semaphore ZK | ElGamal / simplified | Commit-reveal |
