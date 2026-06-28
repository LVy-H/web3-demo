type Env = Record<string, string | undefined>;
function parseFlags(args: string[]): { positional: string[]; flags: Record<string, string> } {
  const positional: string[] = []; const flags: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) { flags[args[i].slice(2)] = args[i + 1]; i++; }
    else positional.push(args[i]);
  }
  return { positional, flags };
}
export async function runCli(argv: string[], env: Env, fetchImpl: typeof fetch = fetch): Promise<{ code: number; out: string }> {
  const base = env.TESSERA_ADMIN_URL ?? "http://127.0.0.1:8786";
  const token = env.TESSERA_OPERATOR_TOKEN ?? "";
  const headers = { authorization: `Bearer ${token}`, "content-type": "application/json" };
  const [cmd, ...rest] = argv;
  const { positional, flags } = parseFlags(rest);
  const call = async (method: string, path: string, body?: unknown) => {
    const res = await fetchImpl(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    return { ok: res.ok, status: res.status, body: (await res.json()) as Record<string, unknown> };
  };
  try {
    switch (cmd) {
      case "create": {
        const r = await call("POST", "/tenants", { slug: positional[0], displayName: flags["display-name"] ?? positional[0] });
        if (!r.ok) return { code: 1, out: `error: ${r.body.error}` };
        return { code: 0, out: `created ${r.body.slug}\n  org admin token (hand to the org): ${r.body.adminToken}` };
      }
      case "list": {
        const r = await call("GET", "/tenants");
        const rows = (r.body.tenants as { slug: string; status: string }[]).map((t) => `${t.slug}\t${t.status}`);
        return { code: 0, out: rows.join("\n") };
      }
      case "suspend": case "resume": {
        const r = await call("POST", `/tenants/${positional[0]}/${cmd}`);
        return r.ok ? { code: 0, out: `${positional[0]} → ${r.body.status}` } : { code: 1, out: `error: ${r.body.error}` };
      }
      case "delete": {
        const q = flags.export ? `?export=${encodeURIComponent(flags.export)}` : "";
        const r = await call("DELETE", `/tenants/${positional[0]}${q}`);
        return r.ok ? { code: 0, out: `deleted ${positional[0]}` } : { code: 1, out: `error: ${r.body.error}` };
      }
      default:
        return { code: 2, out: "usage: tessera-ctl create|list|suspend|resume|delete <slug>" };
    }
  } catch (e) { return { code: 1, out: `error: ${(e as Error).message}` }; }
}
if (require.main === module) {
  runCli(process.argv.slice(2), process.env).then((r) => { process.stdout.write(r.out + "\n"); process.exit(r.code); });
}
