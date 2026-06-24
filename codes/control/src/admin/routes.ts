import express from "express";
import { z } from "zod";
import type { Provisioner } from "../orchestrator/provisioner";
import type { makeRepos } from "../registry/repos";
import { requireOperator } from "./auth";
import { SlugError } from "../slug";
import { DuplicateTenantError } from "../registry/repos";

type Repos = ReturnType<typeof makeRepos>;
const CreateBody = z.object({ slug: z.string(), displayName: z.string().min(1) });

export function createAdminApp(deps: { repos: Repos; provisioner: Provisioner }): express.Express {
  const app = express();
  app.use(express.json());
  app.use(requireOperator(deps.repos));

  app.post("/tenants", async (req, res) => {
    const parsed = CreateBody.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "bad-request", issues: parsed.error.issues }); return; }
    try {
      const { adminToken } = await deps.provisioner.create(parsed.data.slug, parsed.data.displayName);
      res.status(201).json({ slug: parsed.data.slug, adminToken });
    } catch (e) {
      if (e instanceof SlugError) { res.status(400).json({ error: e.message }); return; }
      if (e instanceof DuplicateTenantError) { res.status(409).json({ error: e.message }); return; }
      res.status(500).json({ error: (e as Error).message });
    }
  });

  app.get("/tenants", (_req, res) => res.json({ tenants: deps.repos.tenants.list() }));

  const lifecycle = (fn: (slug: string) => Promise<void>) => async (req: express.Request, res: express.Response) => {
    if (!deps.repos.tenants.get(req.params.slug)) { res.status(404).json({ error: "no-such-org" }); return; }
    try { await fn(req.params.slug); res.json({ slug: req.params.slug, status: deps.repos.tenants.get(req.params.slug)?.status }); }
    catch (e) { res.status(500).json({ error: (e as Error).message }); }
  };
  app.post("/tenants/:slug/suspend", lifecycle((s) => deps.provisioner.suspend(s)));
  app.post("/tenants/:slug/resume", lifecycle((s) => deps.provisioner.resume(s)));
  app.delete("/tenants/:slug", async (req, res) => {
    if (!deps.repos.tenants.get(req.params.slug)) { res.status(404).json({ error: "no-such-org" }); return; }
    try { await deps.provisioner.remove(req.params.slug, typeof req.query.export === "string" ? req.query.export : undefined); res.json({ slug: req.params.slug, deleted: true }); }
    catch (e) { res.status(500).json({ error: (e as Error).message }); }
  });
  return app;
}
