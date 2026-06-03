# Client conventions (Tessera / Flutter)

Conventions for `codes/mobile/` — the Flutter app that is Tessera's sole client
across mobile, desktop, and web. (This supersedes the old React frontend
conventions; that frontend was deleted.)

## Stack

| Tool | Notes |
| --- | --- |
| Flutter / Dart | One codebase for mobile, desktop, and web. |
| go_router | Declarative routing; deep links (`/poll/:address?module=…`, `/verify?…`). |
| flutter_secure_storage | Identity seed, blind-vote salts, organizer keypair — never plaintext prefs. |
| http | Talks to the relayer; the chain is read/written via the data layer's services. |
| webview_flutter | Hosts the ZK prover bundle on mobile (the web build proves in-page). |

## Layered architecture (UI → Logic → Data)

```
lib/
├── core/        Pure logic, no Flutter deps: crypto/ (ticket, survey_commit, …)
│                and voting/ (ranked_irv, quadratic_alloc). Cross-impl with
│                Solidity — covered by golden / cross-impl tests.
├── data/        models/ (DTOs with fromJson/toJson), repositories/ (one per
│                module: approval / ranked / quadratic / survey — each encodes its
│                ballot), services/ (chain reader/writer, relay_client, secure
│                storage, proving).
├── ui/features/ One folder per screen: <feature>_screen.dart (widgets) +
│                <feature>_view_model.dart (state + actions).
├── router.dart  buildPollDetail dispatches on the on-chain module type.
└── config.dart  AppConfig: network / RPC, relayer host, registry address.
```

Rules:

- **One ViewModel per screen**, holding per-poll state. No module-global or
  static mutable state — navigating between polls must not leak state across
  them.
- **Repositories own ballot encoding.** A module's wire format (bitmask /
  ranking / credit vector / answer commitment) lives in its repository plus a
  `core/` helper, and must byte-match the Solidity side. Change one side → change
  the other → re-run the cross-impl tests.
- **Secrets go in secure storage**, never `SharedPreferences`.
- **Widgets stay thin and declarative**; side effects (sign, prove, relay) live
  in the ViewModel, not the widget tree.

## Testing

- `flutter analyze` must be clean and `flutter test` must pass — both are CI
  gates (the `mobile` job).
- Unit/widget tests live under `test/`; on-chain and driver tests under
  `integration_test/` self-skip when no local node / device is present.
- Cross-impl crypto/encoding tests (`core/crypto`, `core/voting`) are
  load-bearing: they pin the Dart ↔ Solidity ↔ relayer agreement.

## Style

- Follow `dart format` / `flutter analyze` defaults; match the surrounding code.
- Visual system and UX: see [`visual-design-guide.md`](./visual-design-guide.md)
  and [`ux-design-principles.md`](./ux-design-principles.md).
