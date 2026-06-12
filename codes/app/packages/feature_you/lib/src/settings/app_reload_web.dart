import 'dart:js_interop';

/// Web: reloading the page re-runs `main()`, which re-loads and re-applies
/// the saved network override. That reload IS the apply step for a hosted
/// build — so the settings screen offers a one-tap "Reload to apply".
const bool canReloadApp = true;

@JS('window')
external _Window get _window;

extension type _Window(JSObject _) implements JSObject {
  external _Location get location;
}

extension type _Location(JSObject _) implements JSObject {
  external void reload();
}

void reloadApp() => _window.location.reload();
