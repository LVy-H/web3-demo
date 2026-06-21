import request from "supertest";
import { describe, it, expect } from "vitest";
import { randomBytes } from "node:crypto";
import { makeTestApp } from "../helpers/app";
import { canonicalize, sha256hex } from "../../src/crypto";
import { merkleRoot } from "../../src/merkle";
import { blind, finalize, type BlindState } from "../../src/credentials";
import {
  verifyDecision,
  type VerifierBundle,
  type Check,
} from "../../src/verifier";

/**
 * §6/§11/§12.2 verifiable SECRET-ballot (anonymous-yet-eligible) flow, e2e:
 *
 *   create(secret)  →  state 'registration', a per-decision RSABSSA-PSS issuer
 *   register        →  client `blind()`s the credential message under the issuer
 *                      pubkey, server `blindSign()`s it, client `finalize()`s →
 *                      a credential signature it can later present anonymously
 *   open            →  registration CLOSES (registration→open); register now 403s
 *   cast            →  present `{ serial, credentialSig }`; server verifyCredential
 *                      + serial-uniqueness (no double-vote), persists serial
 *   close → publish →  final signed checkpoint over the public leaves
 *   GET /verify     →  ok:true, all six §11 checks incl. no-double-vote
 *
 * Adversarial: a forged credential → cast 403 INELIGIBLE; a reused serial → 409.
 *
 * The client-side `blind`/`finalize` here stand in for the (out-of-scope) Flutter
 * secret-ballot UI: Dart has no RSABSSA impl yet, so the credentials module's TS
 * helpers prove the loop. The issuer NEVER sees the final (serial, sig).
 */
describe("e2e: verifiable SECRET-ballot decision flow", () => {
  // The PUBLIC leaf recipe (secret mode: serial = the credential serial).
  const leafOf = (
    decisionId: string,
    logSeq: number,
    payload: unknown,
    serial: string | null,
  ) =>
    sha256hex(
      "tessera:leaf:v1\n" +
        canonicalize({ decisionId, logSeq, payload, serial: serial ?? null }),
    );

  const createBody = {
    title: "Adopt the secret proposal?",
    options: ["Yes", "No"],
    method: "single",
    ballotMode: "secret",
    resultsPolicy: "sealed",
    eligibility: { method: "open" },
    rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
    schedule: {},
    visibility: "listed",
    anchorMode: "broadcast",
  };

  /** A registered voter's anonymous credential, ready to cast. */
  interface Credential {
    serial: string;
    credentialSig: string;
  }

  /**
   * Drive one full registration: pick a random serial, blind the credential
   * message `${decisionId}|${serial}` under the issuer pubkey, POST /register,
   * and finalize the returned blind signature into a credential. The server only
   * ever sees the BLINDED token.
   */
  async function registerVoter(
    app: ReturnType<typeof makeTestApp>["app"],
    decisionId: string,
    issuerPubKeyPem: string,
  ): Promise<Credential> {
    const serial = randomBytes(16).toString("hex");
    const message = `${decisionId}|${serial}`;
    const { blinded, state }: { blinded: string; state: BlindState } =
      await blind(issuerPubKeyPem, message);

    const reg = await request(app)
      .post("/register")
      .send({ decisionId, blindedMessage: blinded });
    expect(reg.status, JSON.stringify(reg.body)).toBe(200);
    expect(typeof reg.body.blindSignature).toBe("string");

    const credentialSig = await finalize(
      issuerPubKeyPem,
      message,
      reg.body.blindSignature,
      state,
    );
    return { serial, credentialSig };
  }

  it("create(secret)→register→open→cast→close→publish→verify ok with all six checks", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) =>
      r.set("Authorization", `Bearer ${adminToken}`);

    // ── create (secret) — lands in 'registration', advertises the issuer ──────
    const createRes = await auth(
      request(app).post("/decisions").send(createBody),
    );
    expect(createRes.status).toBe(201);
    expect(createRes.body.state).toBe("registration");
    expect(typeof createRes.body.issuerPubKeyHash).toBe("string");
    expect(typeof createRes.body.issuerPublicKeyPem).toBe("string");
    const id: string = createRes.body.id;
    const issuerPub: string = createRes.body.issuerPublicKeyPem;

    // The public metadata exposes the SAME issuerPubKeyHash a verifier needs.
    const meta = (await request(app).get(`/decisions/${id}`)).body;
    expect(meta.issuerPubKeyHash).toBe(createRes.body.issuerPubKeyHash);
    expect(meta.state).toBe("registration");

    // ── register 3 voters (blind locally, server blind-signs) ─────────────────
    const creds: Credential[] = [];
    for (let i = 0; i < 3; i++) {
      creds.push(await registerVoter(app, id, issuerPub));
    }
    // The §6 issued-credential ledger now counts 3 issuances.
    const issuedView = (await request(app).get(`/decisions/${id}`)).body;
    expect(issuedView.issuedCount).toBe(3);

    // ── open — registration CLOSES; a late register is rejected ───────────────
    const openRes = await auth(request(app).post(`/decisions/${id}/open`));
    expect(openRes.status).toBe(200);
    expect(openRes.body.state).toBe("open");

    const lateReg = await request(app)
      .post("/register")
      .send({ decisionId: id, blindedMessage: "AAAA" });
    expect(lateReg.status).toBe(409);
    expect(lateReg.body.code).toBe("REGISTRATION_CLOSED");

    // ── cast: 2× Yes, 1× No, each with a credentialed (serial, sig) ───────────
    const payloads = [
      { kind: "single", choice: 0 },
      { kind: "single", choice: 0 },
      { kind: "single", choice: 1 },
    ];
    for (let i = 0; i < 3; i++) {
      const c = creds[i];
      const res = await request(app).post("/ballots").send({
        decisionId: id,
        payload: payloads[i],
        serial: c.serial,
        credentialSig: c.credentialSig,
        idempotencyKey: `cast-${c.serial}`,
      });
      expect(res.status, JSON.stringify(res.body)).toBe(201);
      // The public leaf binds the credential serial (so no-double-vote works).
      expect(res.body.receipt.ballotHash).toBe(
        leafOf(id, i, payloads[i], c.serial),
      );
    }

    // ── /root reflects 3 leaves ───────────────────────────────────────────────
    const root = await request(app).get(`/root`).query({ decisionId: id });
    expect(root.body.treeSize).toBe(3);

    // ── /ballots serves the serials publicly ─────────────────────────────────
    const page = await request(app)
      .get(`/ballots`)
      .query({ decisionId: id, after: -1, limit: 10 });
    expect(page.body.ballots).toHaveLength(3);
    for (let i = 0; i < 3; i++) {
      expect(page.body.ballots[i].serial).toBe(creds[i].serial);
    }
    // Merkle binding holds over the served secret-mode leaves.
    const ordered = [...page.body.ballots].sort(
      (a: { logSeq: number }, b: { logSeq: number }) => a.logSeq - b.logSeq,
    );
    expect(merkleRoot(ordered.map((b: { ballotHash: string }) => b.ballotHash))).toBe(
      root.body.root,
    );

    // ── close → publish ───────────────────────────────────────────────────────
    expect(
      (await auth(request(app).post(`/decisions/${id}/close`))).body.state,
    ).toBe("closed");
    expect(
      (await auth(request(app).post(`/decisions/${id}/publish`))).body.state,
    ).toBe("published");

    // ── GET /verify/:id — ok with all six §11 checks (incl. no-double-vote) ───
    const verify = await request(app).get(`/verify/${id}`);
    expect(verify.status).toBe(200);
    const report = verify.body.report;
    expect(report.ok, JSON.stringify(report.checks)).toBe(true);
    expect(report.checks).toHaveLength(6);
    for (const c of report.checks as Check[]) {
      expect(c.ok, `§11 check '${c.name}' failed: ${c.detail}`).toBe(true);
    }
    // The no-double-vote check actually ran over secret-mode serials.
    const ndv = (report.checks as Check[]).find(
      (c) => c.name === "no-double-vote",
    )!;
    expect(ndv.detail).toMatch(/secret-mode/);
    expect(report.tally.optionScores).toEqual([2, 1]);
    expect(report.verdict.outcome).toBe("carried");
  });

  it("a verifier rebuilds the SECRET bundle from public endpoints and verifyDecision passes (real issuerPubKeyHash)", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) =>
      r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app).post("/decisions").send(createBody),
    );
    const id: string = createRes.body.id;
    const issuerPub: string = createRes.body.issuerPublicKeyPem;
    const c = await registerVoter(app, id, issuerPub);

    await auth(request(app).post(`/decisions/${id}/open`));
    await request(app).post("/ballots").send({
      decisionId: id,
      payload: { kind: "single", choice: 0 },
      serial: c.serial,
      credentialSig: c.credentialSig,
      idempotencyKey: `k-${c.serial}`,
    });
    await auth(request(app).post(`/decisions/${id}/close`));
    await auth(request(app).post(`/decisions/${id}/publish`));

    // Build the bundle purely from public endpoints.
    const meta = (await request(app).get(`/decisions/${id}`)).body;
    const anchor = (await request(app).get(`/anchor`).query({ decisionId: id }))
      .body;
    const results = (
      await request(app).get(`/results`).query({ decisionId: id })
    ).body;
    const key = (await request(app).get(`/key`)).body;
    const ballotsPage = (
      await request(app).get(`/ballots`).query({ decisionId: id, after: -1 })
    ).body;

    // The verifier binds the SECRET decision under the REAL issuerPubKeyHash.
    expect(typeof meta.issuerPubKeyHash).toBe("string");

    const bundle: VerifierBundle = {
      decision: {
        id: meta.id,
        title: meta.title,
        options: meta.options,
        method: meta.method,
        ballotMode: meta.ballotMode,
        resultsPolicy: meta.resultsPolicy,
        rule: meta.rule,
        schedule: meta.schedule,
        visibility: meta.visibility,
        anchorMode: meta.anchorMode,
        rosterCommitment: meta.rosterCommitment,
        issuerPubKeyHash: meta.issuerPubKeyHash,
      },
      setupCommitment: meta.setupCommitment,
      serverPubKeyPem: key.serverPubKeyPem,
      ballots: ballotsPage.ballots.map(
        (b: {
          logSeq: number;
          payload: unknown;
          serial: string | null;
          ballotHash: string;
        }) => ({
          logSeq: b.logSeq,
          payload: b.payload,
          serial: b.serial,
          ballotHash: b.ballotHash,
        }),
      ),
      anchor: {
        root: anchor.root,
        treeSize: anchor.treeSize,
        signedRoot: anchor.signedRoot,
      },
      publishedResult: { tally: results.tally, verdict: results.verdict },
    };

    const report = verifyDecision(bundle);
    expect(report.ok, JSON.stringify(report.checks)).toBe(true);
    expect(bundle.decision.ballotMode).toBe("secret");
  });

  it("a forged/invalid credential is rejected at cast with a signed 403 INELIGIBLE", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) =>
      r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app).post("/decisions").send(createBody),
    );
    const id: string = createRes.body.id;
    await auth(request(app).post(`/decisions/${id}/open`));

    // A credential the issuer never signed (random base64) → 403 INELIGIBLE.
    const forged = randomBytes(300).toString("base64");
    const res = await request(app).post("/ballots").send({
      decisionId: id,
      payload: { kind: "single", choice: 0 },
      serial: "forged-serial",
      credentialSig: forged,
      idempotencyKey: "forged-1",
    });
    expect(res.status).toBe(403);
    expect(res.body.code).toBe("INELIGIBLE");
    // The refusal is server-signed (exhibitable, §10).
    expect(typeof res.body.signature).toBe("string");
    expect(res.body.signature.length).toBeGreaterThan(0);
    // Nothing was recorded.
    const root = await request(app).get(`/root`).query({ decisionId: id });
    expect(root.body.treeSize).toBe(0);
  });

  it("a reused serial (double-vote) is rejected with a signed 409", async () => {
    const { app, adminToken } = makeTestApp();
    const auth = (r: request.Test) =>
      r.set("Authorization", `Bearer ${adminToken}`);

    const createRes = await auth(
      request(app).post("/decisions").send(createBody),
    );
    const id: string = createRes.body.id;
    const issuerPub: string = createRes.body.issuerPublicKeyPem;
    const c = await registerVoter(app, id, issuerPub);
    await auth(request(app).post(`/decisions/${id}/open`));

    // First cast with the credential succeeds.
    const first = await request(app).post("/ballots").send({
      decisionId: id,
      payload: { kind: "single", choice: 0 },
      serial: c.serial,
      credentialSig: c.credentialSig,
      idempotencyKey: "ser-a",
    });
    expect(first.status).toBe(201);

    // A SECOND cast reusing the SAME serial (even a valid credential, different
    // idempotencyKey) is a double-vote → 409, signed.
    const second = await request(app).post("/ballots").send({
      decisionId: id,
      payload: { kind: "single", choice: 1 },
      serial: c.serial,
      credentialSig: c.credentialSig,
      idempotencyKey: "ser-b",
    });
    expect(second.status).toBe(409);
    expect(second.body.code).toBe("SERIAL_USED");
    expect(typeof second.body.signature).toBe("string");

    // Only the FIRST ballot is recorded.
    const root = await request(app).get(`/root`).query({ decisionId: id });
    expect(root.body.treeSize).toBe(1);
  });
});
