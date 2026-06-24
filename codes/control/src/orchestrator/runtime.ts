import { execFile } from "node:child_process";
import { promisify } from "node:util";
const pexec = promisify(execFile);

export interface RunOpts {
  name: string; image: string; network: string; volume: string; mountPath: string;
  env: Record<string, string>; memory: string; cpus: string;
}
export interface ContainerRuntime {
  ensureNetwork(name: string): Promise<void>;
  createVolume(name: string): Promise<void>;
  run(opts: RunOpts): Promise<void>;
  stop(name: string): Promise<void>;
  start(name: string): Promise<void>;
  remove(name: string): Promise<void>;
  removeVolume(name: string): Promise<void>;
  logs(name: string): Promise<string>;
  exportVolume(volume: string, outPath: string): Promise<void>;
}
export type ExecFn = (bin: string, args: string[]) => Promise<{ stdout: string }>;

export function makeCliRuntime(bin: "docker" | "podman", exec: ExecFn = (b, a) => pexec(b, a)): ContainerRuntime {
  const run1 = (args: string[]) => exec(bin, args);
  return {
    async ensureNetwork(name) {
      try { await run1(["network", "inspect", name]); }
      catch { await run1(["network", "create", name]); }
    },
    async createVolume(name) {
      try { await run1(["volume", "inspect", name]); }
      catch { await run1(["volume", "create", name]); }
    },
    async run(o) {
      const args = ["run", "-d", "--name", o.name, "--network", o.network,
        "--restart", "unless-stopped", "--memory", o.memory, "--cpus", o.cpus,
        "-v", `${o.volume}:${o.mountPath}`];
      for (const [k, v] of Object.entries(o.env)) args.push("-e", `${k}=${v}`);
      args.push(o.image);
      await run1(args);
    },
    async stop(name) { await run1(["stop", name]); },
    async start(name) { await run1(["start", name]); },
    async remove(name) { await run1(["rm", "-f", name]); },
    async removeVolume(name) { await run1(["volume", "rm", name]); },
    async logs(name) { return (await run1(["logs", name])).stdout; },
    async exportVolume(volume, outPath) {
      // tar the volume contents via a throwaway alpine container.
      await run1(["run", "--rm", "-v", `${volume}:/data`, "-v", `${outPath}:/out`,
        "alpine", "tar", "czf", "/out/export.tgz", "-C", "/data", "."]);
    },
  };
}
