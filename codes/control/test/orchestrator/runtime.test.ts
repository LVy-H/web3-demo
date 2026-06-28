import { describe, it, expect } from "vitest";
import { makeCliRuntime } from "../../src/orchestrator/runtime";

describe("CliRuntime", () => {
  it("builds a correct `run` command (no shell, arg array)", async () => {
    const seen: string[][] = [];
    const exec = async (_bin: string, args: string[]) => { seen.push(args); return { stdout: "" }; };
    const rt = makeCliRuntime("podman", exec);
    await rt.run({
      name: "tessera-acme", image: "tessera-server:latest", network: "tessera-net",
      volume: "tessera-acme", mountPath: "/app/data",
      env: { PORT: "3001", DATA_DIR: "/app/data" }, memory: "256m", cpus: "0.5",
    });
    const a = seen[0];
    expect(a[0]).toBe("run");
    expect(a).toContain("--name"); expect(a).toContain("tessera-acme");
    expect(a).toContain("--network"); expect(a).toContain("tessera-net");
    expect(a).toContain("--memory"); expect(a).toContain("256m");
    expect(a).toContain("--cpus"); expect(a).toContain("0.5");
    expect(a).toContain("-v"); expect(a).toContain("tessera-acme:/app/data");
    expect(a).toContain("-e"); expect(a).toContain("PORT=3001");
    expect(a).toContain("tessera-server:latest");
    // never publishes a host port:
    expect(a).not.toContain("-p");
  });
});
