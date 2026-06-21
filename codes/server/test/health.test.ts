import request from "supertest";
import { describe, it, expect } from "vitest";
import { makeTestApp } from "./helpers/app";

describe("GET /health", () => {
  it("returns ok", async () => {
    const { app } = makeTestApp();
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok" });
  });
});
