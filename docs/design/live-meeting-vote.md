# Live Meeting Vote

The original live-meeting design was written for the retired
on-chain/Semaphore/relayer prototype. It described rotating QR tickets,
face-to-face confirmation, relayer ticket redemption, and chain registration.

That design is no longer the current implementation reference.

## Current Status

Tessera's active product path is the self-hosted server plus Flutter client:

- decisions are created on the REST server;
- ballots are appended to the server's verifiable log;
- results are recomputed from public ballot data;
- verification checks the signed Merkle/anchor bundle;
- secret ballots use blind-signature credentials, not Semaphore proofs.

The app still has route and UI seams for live/join flows, but a current
server-backed live-meeting protocol needs a fresh design against the REST server
model before it should be presented as shipped behavior.

## Current Design Direction

A server-backed live meeting should be built from these primitives:

- Convener-created decision in registration or draft state.
- Short-lived join tickets signed by the server or convener.
- Human confirmation code shown to the voter and organizer.
- Server-side admission record that can be audited without exposing vote choice.
- Ballot casting through the normal `/ballots` endpoint.
- Public verification through `/verify/:id`.

## Non-goals for the Current Demo

- No relayer ticket redemption.
- No chain registration.
- No wallet setup.
- No proof-of-presence hardware dependency.

Until a new server-backed live-meeting spec is written, demo the main product
flow with `./demo.sh up`: create a decision, cast ballots, close/publish, and
verify.
