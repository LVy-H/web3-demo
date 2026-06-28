import { describe, it, expect } from "vitest";
import { loadConfig } from "../src/config";

describe("loadConfig", () => {
  it("applies localhost-first defaults", () => {
    const c = loadConfig({});
    expect(c.port).toBe(8787);
    expect(c.runtime).toBe("docker");
    expect(c.image).toBe("tessera-server:latest");
    expect(c.network).toBe("tessera-net");
    expect(c.tenantMemory).toBe("256m");
    expect(c.tenantCpus).toBe("0.5");
    expect(c.baseDomain).toBe("localhost");
  });
  it("reads overrides and rejects an unknown runtime", () => {
    expect(loadConfig({ TESSERA_RUNTIME: "podman" }).runtime).toBe("podman");
    expect(() => loadConfig({ TESSERA_RUNTIME: "lxc" })).toThrow(/runtime/i);
  });
});
