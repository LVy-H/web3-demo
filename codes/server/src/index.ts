import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { createApp } from "./app";
import { openDb, migrate, makeRepos } from "./db";
import { loadOrCreateServerKey } from "./crypto";
import { bootstrapAdmin } from "./auth";

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

createApp({ db, repos, serverKey }).listen(PORT, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`Tessera server running on port ${PORT}`);
});
