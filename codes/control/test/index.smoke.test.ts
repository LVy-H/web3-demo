import { describe, it, expect } from "vitest";
import { buildControlPlane } from "../src/index";
import { loadConfig } from "../src/config";

describe("buildControlPlane", () => {
  it("mints an operator token on first build and wires both apps", () => {
    const cp = buildControlPlane(loadConfig({ DATA_DIR: ":memory:" }));
    expect(cp.bootstrapToken).toMatch(/.{20,}/);
    expect(typeof cp.adminApp).toBe("function");      // express app
    expect(cp.proxyServer.listen).toBeTypeOf("function"); // http.Server
  });
});
