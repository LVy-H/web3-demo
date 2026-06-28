# Using Tessera - End-user / Demo-runner Guide

This guide follows the current Tessera product: one self-hosted server plus one
Flutter client. There is no local chain, contract deployment, wallet, MetaMask,
relayer, or ZK prover in the default demo path.

Tessera lets a group create a decision, cast ballots, close/publish the result,
and verify the published count against the public ballot log and signed anchor.

## Run the Demo

From the repository root:

```bash
./demo.sh up
```

The script:

- starts the Tessera server on `http://127.0.0.1:3001`;
- builds and serves the Flutter web app on `http://127.0.0.1:8080`;
- prints the admin token needed for organizer actions.

Open the app:

```text
http://127.0.0.1:8080/
```

Then go to Settings -> Network, confirm the server URL is
`http://127.0.0.1:3001`, and paste the admin token printed by `./demo.sh up`.

Stop the demo:

```bash
./demo.sh down
```

Check status:

```bash
./demo.sh status
```

## Development Run

If you want the server and Flutter runner in separate terminals:

```bash
./dev-stack.sh up
```

Then:

```bash
cd codes/app/apps/tessera
flutter run -d chrome
```

The web build is the easiest target for demoing the full flow. Desktop/mobile
targets may still have route and storage coverage, but the one-command demo is
the canonical local path.

## App Areas

The app is organized around three main spaces plus join/verify task routes:

| Area | What it does |
| --- | --- |
| Vote | Browse or open known decisions and cast a ballot. |
| Organize | Create decisions, monitor turnout, close and publish results. |
| You | Receipts, settings, diagnostics, and verification entry points. |
| Join | Resolve shared links/codes into a decision or live flow. |

## Create a Decision

1. Open Organize -> Create.
2. Pick a method:
   - Single choice.
   - Approval.
   - Ranked choice.
   - Quadratic.
   - Survey.
3. Enter a title and at least two options.
4. Create the decision.

In server mode, creation uses the admin token pasted in Settings -> Network. The
open-ballot demo creates the decision on the REST server and opens it for voting
without requiring a wallet.

## Vote

Open a decision from the app or a shared link, then cast the ballot for that
method:

- Single choice: pick one option.
- Approval: select any number of options.
- Ranked: order options by preference.
- Quadratic: allocate votes within the 100-credit budget.
- Survey: answer the configured options.
- Abstain: counted toward turnout without adding option score.

The server records each accepted ballot in an append-only log and returns a
signed receipt containing the ballot hash, log position, running Merkle root,
and server signature.

## Close, Publish, and Results

From the organizer view:

1. Close the decision when voting is done.
2. Publish results.
3. Review turnout and tally.

Results are recomputed from the public ballot set. The server's `/results`
response is a convenience view, not the trust root.

## Verify

Anyone can verify a decision through:

```bash
curl http://127.0.0.1:3001/verify/<decision-id>
```

The verifier rebuilds the public bundle and checks the setup commitment, ballot
hashes, Merkle root, signed anchor, tally, verdict, and secret-ballot
no-double-vote constraints where applicable.

The app also exposes verification through the You/Verify flow.

## Secret Ballots

Secret-ballot support uses per-decision RFC 9474 RSABSSA blind-signature
credentials:

1. A voter registers while the decision is in registration.
2. The client blinds the credential message locally.
3. The server blind-signs the opaque token.
4. The voter finalizes the credential client-side.
5. The cast presents an anonymous `(serial, credentialSig)` pair.

The server can verify eligibility and prevent duplicate serials without seeing
the final credential during issuance. The documented caveat remains: this does
not protect against all timing/metadata correlation by a live malicious host.

## Static Site

The marketing site is separate from the app:

```bash
python3 -m http.server 8080 --directory site
```

Then visit `http://localhost:8080`. To build the Flutter app into
`site/demo/`, run:

```bash
./demo.sh build
```

## More Docs

- [`README.md`](README.md) - project overview and one-command demo.
- [`codes/README.md`](codes/README.md) - code workspace orientation.
- [`deploy/README.md`](deploy/README.md) - self-hosting.
- [`deploy/multi-tenant/README.md`](deploy/multi-tenant/README.md) - multi-tenant localhost demo.
- [`docs/project/STATUS.md`](docs/project/STATUS.md) - current status and remaining work.
