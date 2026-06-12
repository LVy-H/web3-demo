// Unit tests for the rate-limit env overrides (RELAY_RATE_LIMIT_MAX /
// RELAY_RATE_LIMIT_WINDOW_MS) and the sponsored daily-cap overrides
// (RELAY_CREATE_DAILY_MAX / RELAY_REGISTER_PER_POLL_MAX). `config` is a frozen
// snapshot taken at module import, so each case resets the module registry and
// re-imports to observe the env at import time. setup.ts already provides
// RELAYER_PRIVATE_KEY.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const ENV_KEYS = [
    "RELAY_RATE_LIMIT_MAX",
    "RELAY_RATE_LIMIT_WINDOW_MS",
    "RELAY_CREATE_DAILY_MAX",
    "RELAY_REGISTER_PER_POLL_MAX",
    "CREATE_DAILY_MAX",
    "REGISTER_PER_POLL_MAX",
] as const;
const saved: Record<string, string | undefined> = {};

async function freshConfig() {
    vi.resetModules();
    return (await import("../src/config")).config;
}

async function freshModule() {
    vi.resetModules();
    return await import("../src/config");
}

describe("config rate-limit env overrides", () => {
    beforeEach(() => {
        for (const k of ENV_KEYS) {
            saved[k] = process.env[k];
            delete process.env[k];
        }
    });

    afterEach(() => {
        for (const k of ENV_KEYS) {
            if (saved[k] === undefined) delete process.env[k];
            else process.env[k] = saved[k];
        }
        vi.resetModules();
    });

    it("defaults to 20 req / 60s when env vars are unset (production default)", async () => {
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(20);
        expect(config.rateLimitWindowMs).toBe(60_000);
    });

    it("RELAY_RATE_LIMIT_MAX overrides the request cap", async () => {
        process.env.RELAY_RATE_LIMIT_MAX = "600";
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(600);
        expect(config.rateLimitWindowMs).toBe(60_000); // window untouched
    });

    it("RELAY_RATE_LIMIT_WINDOW_MS overrides the window", async () => {
        process.env.RELAY_RATE_LIMIT_WINDOW_MS = "1000";
        const config = await freshConfig();
        expect(config.rateLimitWindowMs).toBe(1_000);
        expect(config.rateLimitMax).toBe(20); // cap untouched
    });

    it("falls back to defaults on non-numeric or zero values", async () => {
        process.env.RELAY_RATE_LIMIT_MAX = "not-a-number";
        process.env.RELAY_RATE_LIMIT_WINDOW_MS = "0";
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(20);
        expect(config.rateLimitWindowMs).toBe(60_000);
    });
});

describe("config sponsored daily-cap env overrides", () => {
    beforeEach(() => {
        for (const k of ENV_KEYS) {
            saved[k] = process.env[k];
            delete process.env[k];
        }
    });

    afterEach(() => {
        for (const k of ENV_KEYS) {
            if (saved[k] === undefined) delete process.env[k];
            else process.env[k] = saved[k];
        }
        vi.resetModules();
    });

    it("defaults to 5 creates/day and 50 registers/day when unset (production defaults)", async () => {
        const mod = await freshModule();
        expect(mod.config.createDailyMax).toBe(5);
        expect(mod.config.registerPerPollMax).toBe(50);
        expect(mod.getCreateDailyMax()).toBe(5);
        expect(mod.getRegisterPerPollMax()).toBe(50);
    });

    it("RELAY_CREATE_DAILY_MAX overrides the create cap (frozen config + live getter)", async () => {
        process.env.RELAY_CREATE_DAILY_MAX = "1000";
        const mod = await freshModule();
        expect(mod.config.createDailyMax).toBe(1000);
        expect(mod.getCreateDailyMax()).toBe(1000);
        expect(mod.config.registerPerPollMax).toBe(50); // register cap untouched
    });

    it("RELAY_REGISTER_PER_POLL_MAX overrides the register cap (frozen config + live getter)", async () => {
        process.env.RELAY_REGISTER_PER_POLL_MAX = "500";
        const mod = await freshModule();
        expect(mod.config.registerPerPollMax).toBe(500);
        expect(mod.getRegisterPerPollMax()).toBe(500);
        expect(mod.config.createDailyMax).toBe(5); // create cap untouched
    });

    it("legacy unprefixed names still work, RELAY_* takes precedence", async () => {
        process.env.CREATE_DAILY_MAX = "7";
        process.env.REGISTER_PER_POLL_MAX = "70";
        let mod = await freshModule();
        expect(mod.getCreateDailyMax()).toBe(7);
        expect(mod.getRegisterPerPollMax()).toBe(70);

        process.env.RELAY_CREATE_DAILY_MAX = "9";
        process.env.RELAY_REGISTER_PER_POLL_MAX = "90";
        mod = await freshModule();
        expect(mod.getCreateDailyMax()).toBe(9);
        expect(mod.getRegisterPerPollMax()).toBe(90);
    });

    it("falls back to defaults on non-numeric or zero values", async () => {
        process.env.RELAY_CREATE_DAILY_MAX = "not-a-number";
        process.env.RELAY_REGISTER_PER_POLL_MAX = "0";
        const mod = await freshModule();
        expect(mod.config.createDailyMax).toBe(5);
        expect(mod.config.registerPerPollMax).toBe(50);
    });
});
