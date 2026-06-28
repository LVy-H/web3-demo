#!/usr/bin/env node
/**
 * Tessera independent-verifier CLI (§11).
 *
 * Reads a decision bundle as JSON from a file path (argv[2]) or, if none is
 * given, from stdin; runs `verifyDecision`; prints a human-readable report; and
 * exits non-zero when the bundle does NOT verify. This is the "run it yourself"
 * entrypoint — the integration wires it as the `verify` npm script.
 *
 * Usage:
 *   ts-node src/verifier/cli.ts path/to/bundle.json
 *   cat bundle.json | ts-node src/verifier/cli.ts
 *
 * The CLI only reads a bundle file — it makes no network calls and shares no
 * state with the server. That isolation is the whole point: an independent
 * verifier proves nothing if it trusts the host it is checking.
 */

import { readFileSync } from "node:fs";
import { verifyDecision, type VerifierBundle } from "./verifyDecision";

function readBundleSource(argv: string[]): string {
  const path = argv[2];
  if (path && path !== "-") {
    return readFileSync(path, "utf8");
  }
  // No path (or "-") → read the whole of stdin.
  return readFileSync(0, "utf8");
}

function formatReport(report: ReturnType<typeof verifyDecision>): string {
  const lines: string[] = [];
  const banner = report.ok ? "VERIFIED ✓" : "FAILED ✗";
  lines.push(`Tessera independent verifier — decision ${report.decisionId || "(unknown)"}`);
  lines.push(`Result: ${banner}`);
  lines.push("");
  lines.push("Checks (§11):");
  for (const c of report.checks) {
    const mark = c.ok ? "PASS" : "FAIL";
    lines.push(`  [${mark}] ${c.name}`);
    lines.push(`         ${c.detail}`);
  }
  lines.push("");
  lines.push("Recomputed tally:");
  lines.push(`  method=${report.tally.method} options=${report.tally.optionCount}`);
  lines.push(`  optionScores=${JSON.stringify(report.tally.optionScores)}`);
  lines.push(`  abstain=${report.tally.abstain} totalCast=${report.tally.totalCast}`);
  if (report.tally.winner !== undefined) {
    lines.push(`  irvWinner=${String(report.tally.winner)}`);
  }
  lines.push("Recomputed verdict:");
  lines.push(`  outcome=${report.verdict.outcome}${
    report.verdict.winner !== undefined ? ` winner=${report.verdict.winner}` : ""
  }${report.verdict.tiedOptions ? ` tied=${JSON.stringify(report.verdict.tiedOptions)}` : ""}`);
  return lines.join("\n");
}

function main(): number {
  let raw: string;
  try {
    raw = readBundleSource(process.argv);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`verify: could not read bundle: ${msg}\n`);
    return 2;
  }

  let bundle: VerifierBundle;
  try {
    bundle = JSON.parse(raw) as VerifierBundle;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`verify: bundle is not valid JSON: ${msg}\n`);
    return 2;
  }

  // verifyDecision never throws — a tampered bundle becomes failed checks.
  const report = verifyDecision(bundle);
  process.stdout.write(formatReport(report) + "\n");
  return report.ok ? 0 : 1;
}

process.exit(main());
