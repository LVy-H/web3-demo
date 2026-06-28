# Tessera Flutter App

The Tessera client app for voters, organizers, and verifiers.

This app defaults to the current server-backed product path:

- `SERVER_MODE=true`
- `SERVER_URL=http://127.0.0.1:3001`
- no wallet required for the local demo
- organizer actions use the server admin token pasted in Settings -> Network

## Run

From the repository root, the full local product demo is:

```bash
./demo.sh up
```

For app development with a separately running server:

```bash
./dev-stack.sh up
cd codes/app/apps/tessera
flutter run -d chrome
```

To point a build at a specific server:

```bash
flutter run -d chrome --dart-define=SERVER_URL=http://127.0.0.1:3001
```

## Build Web

```bash
flutter build web --dart-define=SERVER_URL=http://127.0.0.1:3001
```

The repository-level `./demo.sh build` command builds this app and copies the
web bundle into `site/demo/` for static hosting.
