import path from "node:path";
import express from "express";
import http from "node:http";
import { loadConfig, type ControlConfig } from "./config";
import { openDb, migrate } from "./registry/db";
import { makeRepos } from "./registry/repos";
import { makeCliRuntime } from "./orchestrator/runtime";
import { makeProvisioner } from "./orchestrator/provisioner";
import { createAdminApp } from "./admin/routes";
import { createProxyServer } from "./proxy/proxy";
import { bootstrapOperator } from "./admin/auth";

export function buildControlPlane(config: ControlConfig): {
  adminApp: express.Express; proxyServer: http.Server; bootstrapToken: string | null;
} {
  const dbPath = config.dataDir === ":memory:" ? ":memory:" : path.join(config.dataDir, "control.db");
  const db = openDb(dbPath); migrate(db);
  const repos = makeRepos(db);
  const runtime = makeCliRuntime(config.runtime);
  const provisioner = makeProvisioner({ repos, runtime, config });
  const adminApp = createAdminApp({ repos, provisioner });
  const proxyServer = createProxyServer({ repos, config });
  const bootstrapToken = bootstrapOperator(repos)?.token ?? null;
  return { adminApp, proxyServer, bootstrapToken };
}

if (require.main === module) {
  const config = loadConfig(process.env);
  const cp = buildControlPlane(config);
  if (cp.bootstrapToken) console.log("OPERATOR TOKEN (save this, shown once):", cp.bootstrapToken);
  cp.adminApp.listen(config.adminPort, "127.0.0.1", () => console.log(`admin API on :${config.adminPort}`));
  cp.proxyServer.listen(config.port, "0.0.0.0", () => console.log(`proxy on :${config.port}`));
}
