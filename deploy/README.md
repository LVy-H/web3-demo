# Deploying Tessera

Tessera is two pieces that deploy independently:

1. **The server** (`codes/server`) — the self-hosted verifiable bulletin board:
   the append-only ballot log, the convener lifecycle, RFC-6962 Merkle
   checkpoints, the signed anchor, and the public read/verify API. This is the
   only piece that holds state, so it's the only piece you must run yourself.
2. **The web app + marketing site** (`site/`, with the Flutter client built into
   `site/demo/`) — pure static files. Host them anywhere. The app is re-pointed
   at *your* server URL either at build time or live in **Settings → Network**.

> Want to just see it locally first? From the repo root run **`./demo.sh up`** —
> it builds the web client, starts the server, serves the app, and prints the
> URLs + the admin token. `./demo.sh down` stops it. No cloud, no account.

---

## 1. The server (Docker)

The production compose lives here in `deploy/`. It mounts a **named volume** at
`DATA_DIR` so the ballot log and the server's signing key persist across
restarts.

```bash
cd deploy
docker compose up -d --build
docker compose logs -f server     # the ADMIN TOKEN prints once, on first boot — save it
curl http://localhost:3001/health # → {"status":"ok"}
```

What you get:

- `GET /health` — liveness.
- `GET /key` — the server's advertised Ed25519 public key (the signing identity
  every verifier checks the anchor against).
- `GET /decisions/:id`, `GET /ballots?decisionId=…`, `GET /root?decisionId=…`,
  `GET /results?decisionId=…`, `GET /anchor?decisionId=…` — the public read API.
- `GET /verify/:id` — assembles the public bundle and runs the independent
  verifier server-side (non-authoritative convenience; the point is anyone can
  run the same verifier themselves — see below).
- The convener (write) routes are gated by the **admin token** printed once on
  first boot. Paste it into the app under **Settings → Network**.

### Data persistence — read this

Everything trustworthy about Tessera lives under `DATA_DIR`:

- `tessera.db` — the append-only ballot log + decision lifecycle (SQLite).
- the server's Ed25519 **signing key** — its stable public identity.

The compose file mounts these in the `tessera-data` named volume. **If you lose
that volume you lose the server's identity** (published anchors no longer verify
against a fresh key) **and the ballot history.** Back it up:

```bash
docker run --rm -v deploy_tessera-data:/data -v "$PWD":/out alpine \
  tar czf /out/tessera-data-backup.tgz -C /data .
```

### Without Docker

```bash
cd codes/server
npm ci
npm run build           # tsc → dist/ (uses tsconfig.build.json: emits src only)
DATA_DIR=/var/lib/tessera PORT=3001 node dist/index.js
```

Put TLS in front of it (Caddy, nginx, or `cloudflared`). The server already
trusts one proxy hop (`trust proxy`, 1) so client IPs are correct under the
rate-limiter.

### Verifying the build/image

```bash
docker compose build                      # or: docker build codes/server
docker compose up -d
curl http://localhost:3001/health         # → {"status":"ok"}
```

(Verified on this machine: image `tessera-server:latest` builds, `/health`
returns `{"status":"ok"}`, `/key` returns the Ed25519 SPKI PEM, and the admin
token prints on startup.)

---

## 2. The static site + web app

The marketing site (`site/`) and the real Flutter web app deploy together as
static files to **any static host** — Cloudflare Pages, GitHub Pages, Netlify,
or an S3/Caddy bucket.

### Build

From the repo root (the Flutter toolchain is in the Nix devShell):

```bash
./demo.sh build      # flutter build web  +  copy build/web → site/demo/
```

That populates `site/demo/` with the CanvasKit web bundle. The marketing pages
in `site/` link to it via the **"▶ Launch the live app"** button in the
**See it in action** section.

> `site/demo/` is a heavy build artifact and is **gitignored** — the deploy step
> rebuilds it; it is never committed.

To bake a specific server URL into the build (so the hosted app talks to your
deployment out of the box):

```bash
cd codes/app/apps/tessera
flutter build web --dart-define=SERVER_URL=https://tessera.example.com
# then copy build/web → site/demo/  (or just run ./demo.sh build after editing the URL)
```

If you don't bake a URL in, the app ships with the loopback default and any
operator re-points it live: **Settings → Network → Server URL** (+ paste the
admin token to convene). One hosted build, many backends — no rebuild needed.

### Publish

Point your static host at the `site/` directory as the publish root. Examples:

| Host               | Publish dir | Notes                                              |
| ------------------ | ----------- | -------------------------------------------------- |
| Cloudflare Pages   | `site`      | Build command: `./demo.sh build`. No framework.    |
| GitHub Pages       | `site`      | Push `site/` (with built `site/demo/`) to the Pages branch. |
| Netlify            | `site`      | Build: `./demo.sh build`; Publish dir: `site`.     |

Because the app is plain static files, you can also self-host it on the **same
box** as the server behind one reverse proxy (`/` → site, `/api` → :3001).

---

## Putting it together

1. `cd deploy && docker compose up -d --build` → server live, save the admin token.
2. `./demo.sh build` → `site/demo/` populated with the web app.
3. Deploy `site/` to your static host.
4. Open the site → **▶ Launch the live app** → **Settings → Network** → set the
   Server URL to your deployment and paste the admin token to convene a decision.
5. Anyone can check a published result: `cd codes/server && npm run verify -- <bundle.json>`
   → `VERIFIED ✓` (all six checks). You never take the host's word for it.
