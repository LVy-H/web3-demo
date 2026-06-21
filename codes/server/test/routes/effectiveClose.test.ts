import { describe, it, expect } from "vitest";
import { effectiveClose } from "../../src/routes/effectiveClose";
import type { LifecycleEvent } from "../../src/db";

function ev(over: Partial<LifecycleEvent>): LifecycleEvent {
  return {
    id: "x",
    decisionId: "d",
    transition: "open",
    actor: "a",
    ts: 0,
    signedSig: "s",
    closesAt: null,
    ...over,
  };
}

describe("effectiveClose (M2)", () => {
  it("returns the schedule close when there is no extend", () => {
    expect(effectiveClose([], { closesAt: 1000 })).toBe(1000);
  });

  it("returns null when neither a schedule close nor an extend exists", () => {
    expect(effectiveClose([], {})).toBeNull();
    expect(effectiveClose([ev({ transition: "open" })], {})).toBeNull();
  });

  it("an extend's closesAt overrides the schedule", () => {
    const events = [ev({ transition: "extend", ts: 10, closesAt: 5000 })];
    expect(effectiveClose(events, { closesAt: 1000 })).toBe(5000);
  });

  it("the LATEST extend (highest ts) wins", () => {
    const events = [
      ev({ transition: "extend", ts: 10, closesAt: 5000 }),
      ev({ transition: "extend", ts: 30, closesAt: 9000 }),
      ev({ transition: "extend", ts: 20, closesAt: 7000 }),
    ];
    expect(effectiveClose(events, { closesAt: 1000 })).toBe(9000);
  });

  it("ignores non-extend events when picking the close", () => {
    const events = [
      ev({ transition: "open", ts: 5 }),
      ev({ transition: "extend", ts: 10, closesAt: 4000 }),
      ev({ transition: "closed", ts: 50 }),
    ];
    expect(effectiveClose(events, { closesAt: 1000 })).toBe(4000);
  });
});
