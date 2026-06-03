# Tessera — e2e test coverage matrix

Every feature × user-sequence, mapped to its test. Goal: **nothing untested that
can be tested here.** Device-only / fenced paths are listed explicitly (not hidden).

Run: `flutter test` (unit+widget+self-skipping integration) · with the live stack
(`./dev-stack.sh up`) the on-chain integration tests run · add
`RUN_DESKTOP_PROVER=1` to run the sidecar e2e tests (97 total, all green).

## Covered (verified on Linux)

| Feature / sequence | Test | What it proves |
|---|---|---|
| **Browse** — load, filter (ACTIVE/ALL/UPCOMING), empty, error, retry | `ui/.../browse_screen_test` | filters + states; phase/tally per card |
| Browse → poll list from chain | `integration/chain_reader_test` (getAllPolls) | registry struct array decodes |
| Browse → detail → verify (read path) | `integration_test/app_test` (`-d linux`) | live read path vs seeded chain |
| **Poll detail (M1)** — phase, options, results | `ui/.../poll_detail_screen_test` | render + % |
| **M1 anon vote — registered** → proof generates + verifies | `integration/anon_vote_test` | create→registerVoter→startVoting→**proof valid vs real vkey** |
| **M1 anon vote — NOT registered** → clear error, no relay | `ui/.../vote_view_model_test` | membership pre-check, friendly message |
| M1 vote → relay → **lands on-chain + receipt** | `integration/live_meeting_e2e_test` | tally++ AND `isNullifierUsed` true |
| **M2 blind** — create→register→start→commit→end→reveal→tally | `integration/blind_flow_test` | full commit-reveal lands |
| **M2 blind — finalize** (after reveal window) | `integration/blind_finalize_test` | `finalizeResults` → `isFinalized` |
| M2 blind screen per phase (register/commit/reveal) | `ui/.../blind_poll_screen_test` | phase-aware actions |
| M2 commit-hash crypto | `core/crypto/blind_commit_test` | byte-identical to viem/contract golden |
| **Create** (dev-signer) → deploy lands | `integration_test/create_dev_signer_test` (`-d linux`) | wallet bypass + on-chain create |
| **Identity** — create/import/reveal/clear + persist | `integration_test/identity_test` (`-d linux`), `ui/.../identity_*` | real secure store round-trip |
| **Verify** — used / not-found / invalid input | `ui/.../verify_screen_test`, `verify_view_model` (+ live_meeting_e2e receipt) | nullifier lookup |
| **Live-meeting HOST** — org key → QR ticket → queue → confirm | `integration/live_host_test` | confirm = `registerVoter` on-chain |
| **Live-meeting FULL LOOP** — host↔voter→vote lands | `integration/live_meeting_e2e_test` | ticket→commitment→code→postPending→confirm→prove→relay→land |
| Live voter ticket parsing / guards | `ui/.../live_vote_view_model_test` | `?t=` extraction, no-ticket guard |
| **Desktop proving** — proof + verify + commitment | `integration/desktop_prover_test` | sidecar proof vs **real vkey**; commitment golden |
| Ticket / confirmation-code / org-keypair crypto | `core/crypto/{ticket,confirmation_code,org_keypair}_test` | byte-identical to TS golden |
| Relayer client (issue/pending/queue/redeem/vote/status, timeouts) | `data/services/relay_client_test` | exact paths/bodies/parsing |
| Dart-signed ticket ↔ real relayer round-trip | `integration/relay_cross_client_test` | accept → code → redeem consumes |
| Dev-signer tx lands | `integration/chain_writer_test` | sign + broadcast + receipt |
| **Settings** diagnostics | `ui/.../settings_screen_test` | network/signer/proving/version |
| **Proximity** seam (no-op where unsupported) | `data/services/proximity_service_test` | inert capability gate |
| **Survey (12d) contract** — commitment recompute, per-question validation + tally, no-lockout, nullifier/scope/message binding, `getSurveyResults` | `codes/contracts/test/ZkSurveyVoting.test.ts` (45 passing) | full survey ballot logic vs MockVerifier |
| **Survey relayer** — survey-vote request validation (wide commitment `message`, `scope==pollAddress`, answer shape/range, proof shape) | `codes/relayer/test/survey-validation.test.ts` (14 passing) | `validateSurveyVoteRequest` accept/reject |
| **Survey commitment crypto** (Gate 2 cross-impl + abi.encode header + field-element sanity) | `core/crypto/survey_commit_test` (8) | Dart `keccak256(abi.encode(answers))>>8` ≡ ethers ≡ Solidity |
| **Survey init-encoding** ethers cross-check | `data/services/survey_init_encoding_test` (2) | Dart `(uint8,string[])[]` encode ≡ ethers `abi.encode` |
| **Survey stack e2e** — create → register → cast `[2,5]` → per-question `getSurveyResults` non-empty | `codes/contracts/scripts/demo-poll.ts` (survey seed, local chain) | full stack on a real chain, no emulator |
| Contract-level reverts (double-vote, AlreadyRegistered/Committed, HashMismatch, phase guards) | `codes/contracts/test/*` (268 passing) | enforced on-chain |

## Device-only / fenced (cannot be verified on this headless Linux box — flagged, not faked)

| Path | Why | Status |
|---|---|---|
| WalletConnect (Reown) connect + sign | needs a paired mobile wallet | code present; verified only on a device |
| Mobile WebView prover | `webview_flutter`, needs a device/emulator | designed, device-pending |
| **On-device survey UI cast** (browse → survey detail → answer → WebView-prove → relay → per-question results) | needs a device/emulator (same as the WebView prover) | data + contract + relayer + Dart-crypto + stack-e2e paths verified; the on-device UI cast is device-pending (same bound as every module's on-device proving) |
| BLE/NFC proximity radio | needs Android + a beacon/tag | capability-gated no-op; Android impl device-pending |

## Known feature gaps (not test gaps)

- **Create UI deploys only `anon-vote`** — blind polls are created via the contracts/scripts, not the Create screen. (Candidate Phase-9 feature.)
- The live **voter** screen's proving is gated behind `proofServiceAvailable` (web, or desktop with `DESKTOP_PROVER_*`); the data-layer loop is fully covered by `live_meeting_e2e_test`.
