import http from "node:http";
import httpProxy from "http-proxy";
import type { ControlConfig } from "../config";
import type { makeRepos } from "../registry/repos";
import { resolveRoute } from "./hostRouter";
type Repos = ReturnType<typeof makeRepos>;

interface Deps {
  repos: Repos; config: ControlConfig;
  /** test seam: override the upstream URL for a resolved "ok" route. */
  targetOverride?: (target: string) => string;
}
export function createProxyServer(deps: Deps): http.Server {
  const proxy = httpProxy.createProxyServer({ xfwd: true });
  proxy.on("error", (_e, _req, res) => {
    if (res instanceof http.ServerResponse && !res.headersSent) {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: "bad-gateway" }));
    }
  });
  const json = (res: http.ServerResponse, code: number, body: unknown) => {
    res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(body));
  };
  return http.createServer((req, res) => {
    const route = resolveRoute(deps.repos, deps.config, req.headers.host);
    switch (route.kind) {
      case "ok": {
        const target = deps.targetOverride ? deps.targetOverride(route.target) : route.target;
        proxy.web(req, res, { target });
        return;
      }
      case "notFound": return json(res, 404, { error: "no-such-org" });
      case "suspended": return json(res, 503, { error: "org-suspended" });
      case "mismatch": return json(res, 503, { error: "org-key-mismatch" });
      case "badHost": return json(res, 421, { error: "use https://<org>.localhost" });
    }
  });
}
