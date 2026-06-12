// Custom Flutter web bootstrap (template — `flutter build web` substitutes the
// {{...}} tokens; see https://docs.flutter.dev/platform-integration/web/initialization).
//
// Why it exists: the generated default fetches CanvasKit from
// https://www.gstatic.com/flutter-canvaskit/<rev>/ — a third-party origin on
// the critical path (extra DNS + TLS handshake before the first frame, no
// cross-site cache benefit since browsers partition caches, breaks offline /
// strict-CSP hosting). The build already ships the exact same CanvasKit under
// build/web/canvaskit/, so pin the loader to the self-hosted copy and let our
// host's compression + immutable caching apply to it.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Relative to <base href> — the loader still picks the right variant
    // (chromium/ subdirectory on Blink) underneath this base.
    canvasKitBaseUrl: "canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
