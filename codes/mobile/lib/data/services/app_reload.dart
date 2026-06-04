// Web pulls the js_interop reload; every other target gets the native no-op.
// Keeps dart:js_interop out of native compiles (mirrors proof_service_factory).
export 'app_reload_stub.dart'
    if (dart.library.js_interop) 'app_reload_web.dart';
