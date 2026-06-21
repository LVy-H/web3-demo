import { describe, it, expect } from "vitest";
import { canonicalize } from "../../src/crypto";

describe("canonicalize", () => {
  it("produces identical output regardless of object key insertion order", () => {
    const a = canonicalize({ b: 1, a: 2, c: 3 });
    const b = canonicalize({ c: 3, a: 2, b: 1 });
    expect(a).toBe(b);
  });

  it("sorts keys recursively in nested objects", () => {
    const out = canonicalize({ z: { y: 1, x: 2 }, a: { d: 3, c: 4 } });
    expect(out).toBe('{"a":{"c":4,"d":3},"z":{"x":2,"y":1}}');
  });

  it("emits no insignificant whitespace", () => {
    const out = canonicalize({ a: 1, b: [1, 2, 3] });
    expect(out).toBe('{"a":1,"b":[1,2,3]}');
    expect(out).not.toMatch(/\s/);
  });

  it("treats whitespace in the SOURCE value as irrelevant (semantic, not textual)", () => {
    // Two structurally-equal values built differently must canonicalize identically.
    const fromLiteral = canonicalize({ name: "alice", tags: ["x", "y"] });
    const fromParse = canonicalize(
      JSON.parse('{\n  "tags": [ "x" , "y" ],\n  "name": "alice"\n}'),
    );
    expect(fromLiteral).toBe(fromParse);
  });

  it("preserves array order (order IS significant)", () => {
    expect(canonicalize([1, 2, 3])).not.toBe(canonicalize([3, 2, 1]));
    expect(canonicalize([1, 2, 3])).toBe("[1,2,3]");
    expect(canonicalize(["b", "a"])).toBe('["b","a"]');
  });

  it("does NOT sort arrays even when they contain objects", () => {
    const out = canonicalize([{ b: 1 }, { a: 2 }]);
    expect(out).toBe('[{"b":1},{"a":2}]');
  });

  it("serializes primitives canonically", () => {
    expect(canonicalize(null)).toBe("null");
    expect(canonicalize(true)).toBe("true");
    expect(canonicalize(false)).toBe("false");
    expect(canonicalize("hi")).toBe('"hi"');
    expect(canonicalize(0)).toBe("0");
    expect(canonicalize(-5)).toBe("-5");
  });

  it("formats numbers stably (integers and negatives)", () => {
    expect(canonicalize(42)).toBe("42");
    expect(canonicalize(1000000)).toBe("1000000");
    expect(canonicalize(-1)).toBe("-1");
    // -0 normalizes to 0 (JSON has no negative zero)
    expect(canonicalize(-0)).toBe("0");
  });

  it("rejects undefined", () => {
    expect(() => canonicalize(undefined)).toThrow();
  });

  it("rejects functions", () => {
    expect(() => canonicalize(() => 1)).toThrow();
  });

  it("rejects NaN and Infinity", () => {
    expect(() => canonicalize(NaN)).toThrow();
    expect(() => canonicalize(Infinity)).toThrow();
    expect(() => canonicalize(-Infinity)).toThrow();
  });

  it("rejects undefined / function values nested inside objects", () => {
    expect(() => canonicalize({ a: undefined })).toThrow();
    expect(() => canonicalize({ a: () => 1 })).toThrow();
    expect(() => canonicalize({ a: { b: NaN } })).toThrow();
  });

  it("rejects undefined / function entries nested inside arrays", () => {
    expect(() => canonicalize([1, undefined])).toThrow();
    expect(() => canonicalize([() => 1])).toThrow();
  });

  it("escapes special string characters per JSON", () => {
    expect(canonicalize('a"b')).toBe('"a\\"b"');
    expect(canonicalize("a\nb")).toBe('"a\\nb"');
  });
});
