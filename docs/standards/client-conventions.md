# Client Conventions

The canonical client is the Flutter workspace under `codes/app/`. It talks to
the Tessera REST server by default and keeps legacy chain-oriented seams only as
inactive compatibility code.

## App Shape

- `apps/tessera/` owns app shell, routing, dependency injection, and platform
  startup.
- `packages/core_domain/` owns pure journey and voting logic.
- `packages/core_relay/` contains HTTP clients, including the active
  `ServerClient` for the Tessera server.
- `packages/core_storage/` owns local persistence.
- `packages/feature_*` packages own feature screens and adapters.
- `packages/design_system/` owns shared visual primitives.

## Network Configuration

- The default server URL is compiled with `SERVER_URL`.
- The effective server URL can be changed in Settings -> Network.
- Organizer routes require the server admin token. The token is pasted in
  Settings -> Network and kept in memory for the current app run.
- The default demo path does not require a wallet, chain RPC, registry address,
  relayer, or prover.

## Routing

- `/vote` is the voter space.
- `/organize` and `/organize/create` are organizer flows.
- `/you` and `/you/verify` are personal/verification surfaces.
- `/poll/:address` treats `address` as the server decision id in server mode.
- `/join` resolves shared links/codes.

## Testing

- Package tests live beside each package under `test/`.
- App shell/routing tests live under `codes/app/apps/tessera/test/`.
- Prefer pure domain tests for state machines and widget tests for UI behavior.
- Network behavior should be covered through typed client tests and fake clients,
  with a small number of live server-client tests where the boundary matters.
