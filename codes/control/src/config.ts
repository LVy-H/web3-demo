export interface ControlConfig {
  port: number; adminPort: number;
  runtime: "docker" | "podman"; image: string; network: string;
  instancePort: number; tenantMemory: string; tenantCpus: string;
  dataDir: string; baseDomain: string;
}
export function loadConfig(env: NodeJS.ProcessEnv): ControlConfig {
  const runtime = env.TESSERA_RUNTIME ?? "docker";
  if (runtime !== "docker" && runtime !== "podman")
    throw new Error(`unsupported runtime '${runtime}' (use docker|podman)`);
  const num = (v: string | undefined, d: number) => (v ? Number(v) : d);
  return {
    port: num(env.PORT, 8787),
    adminPort: num(env.ADMIN_PORT, 8786),
    runtime,
    image: env.TESSERA_IMAGE ?? "tessera-server:latest",
    network: env.TESSERA_NETWORK ?? "tessera-net",
    instancePort: num(env.TESSERA_INSTANCE_PORT, 3001),
    tenantMemory: env.TESSERA_TENANT_MEM ?? "256m",
    tenantCpus: env.TESSERA_TENANT_CPUS ?? "0.5",
    dataDir: env.DATA_DIR ?? "/app/control-data",
    baseDomain: env.TESSERA_BASE_DOMAIN ?? "localhost",
  };
}
