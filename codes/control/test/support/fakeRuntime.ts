import type { ContainerRuntime, RunOpts } from "../../src/orchestrator/runtime";
export class FakeRuntime implements ContainerRuntime {
  calls: string[] = [];
  running = new Set<string>();
  volumes = new Set<string>();
  logsText = "ADMIN TOKEN (save this, shown once): TENANTTOK\nTessera server running on port 3001";
  failRunFor?: string;
  async ensureNetwork(n: string) { this.calls.push(`net:${n}`); }
  async createVolume(n: string) { this.calls.push(`vol+:${n}`); this.volumes.add(n); }
  async run(o: RunOpts) {
    this.calls.push(`run:${o.name}`);
    if (this.failRunFor === o.name) throw new Error("run failed");
    this.running.add(o.name);
  }
  async stop(n: string) { this.calls.push(`stop:${n}`); this.running.delete(n); }
  async start(n: string) { this.calls.push(`start:${n}`); this.running.add(n); }
  async remove(n: string) { this.calls.push(`rm:${n}`); this.running.delete(n); }
  async removeVolume(n: string) { this.calls.push(`vol-:${n}`); this.volumes.delete(n); }
  async logs(n: string) { this.calls.push(`logs:${n}`); return this.logsText; }
  async exportVolume(v: string, out: string) { this.calls.push(`export:${v}:${out}`); }
}
