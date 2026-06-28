import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { createApp } from "./app";
import { openDb, migrate, makeRepos } from "./db";
import { loadOrCreateServerKey } from "./crypto";
import { bootstrapAdmin } from "./auth";
import { reconcileExpiredDecisions } from "./routes/reconcile";

/**
 * Process entry point: open the persistent DB from `DATA_DIR`, migrate, load
 * (or mint) the server signing key, bootstrap the admin token (printed once),
 * and start listening. All wiring concerns live here; `createApp` is pure.
 */
const DATA_DIR = process.env.DATA_DIR ?? "./data";
const PORT = Number(process.env.PORT ?? 3001);

mkdirSync(DATA_DIR, { recursive: true });

const db = openDb(join(DATA_DIR, "tessera.db"));
migrate(db);
const serverKey = loadOrCreateServerKey(DATA_DIR);
const repos = makeRepos(db);

const { token } = bootstrapAdmin(db, repos);
if (token) {
  // eslint-disable-next-line no-console
  console.log("ADMIN TOKEN (save this, shown once):", token);
}

// §12.5 (M2): a server that was DOWN past a decision's effective close must NOT
// re-open accepting late ballots. Auto-close every open decision whose close has
// already passed (signed lifecycle event + state flip) before we listen.
const reconciled = reconcileExpiredDecisions({ repos, serverKey, now: () => Date.now() });
if (reconciled.length > 0) {
  // eslint-disable-next-line no-console
  console.log(`Reconcile: auto-closed ${reconciled.length} expired decision(s).`);
}

createApp({ db, repos, serverKey }).listen(PORT, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`Tessera server running on port ${PORT}`);
});
