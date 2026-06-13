/// OS deep-link → router bridge (closes the share/JOIN loop on Android).
///
/// The SHARE sheet, QR codes, and `TES-XXXXXX` codes all encode the Tessera
/// link grammar (`feature_join`). Producing those links is only half the loop:
/// something on the device must *consume* a tapped/scanned link and open the
/// right screen. That is this service.
///
/// We deliberately bypass go_router's built-in platform deep-link parsing: the
/// custom scheme encodes the first path segment as the URI *host*
/// (`tessera://poll/<addr>` → host=`poll`), which a path-based parser
/// mishandles. Instead we take the raw URI and run it through the SAME tested
/// pipeline the in-app JOIN scanner uses — `parseJoinInput` (total, never
/// throws) → `locationForJoinTarget` — so an unrecognized or hostile link
/// degrades to the `/error` route exactly like a bad QR scan does.
///
/// Fully injectable for tests: the link source is a [DeepLinkSource] interface
/// (production binds `app_links`; tests supply a fake stream + initial future)
/// and navigation is a plain callback (production passes `router.go`; tests
/// pass a spy). Nothing here touches a platform channel under test.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:feature_join/feature_join.dart';

import 'join_routing.dart';

/// Source of OS-delivered deep links, abstracted so production binds the
/// `app_links` plugin and tests inject fakes with no platform channel.
abstract interface class DeepLinkSource {
  /// The link that cold-started the app, or `null` for a normal launch.
  Future<Uri?> initialLink();

  /// Links delivered while the app is already running (warm re-entry —
  /// `MainActivity` is `singleTop`, so these arrive here, not as a new task).
  Stream<Uri> linkStream();
}

/// Production [DeepLinkSource] backed by the `app_links` plugin singleton.
class AppLinksSource implements DeepLinkSource {
  AppLinksSource([AppLinks? appLinks]) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> linkStream() => _appLinks.uriLinkStream;
}

/// Listens for OS deep links and navigates the router to the matching screen.
class DeepLinkService {
  DeepLinkService({
    required DeepLinkSource source,
    required void Function(String location) navigate,
  }) : _source = source,
       _navigate = navigate;

  final DeepLinkSource _source;
  final void Function(String location) _navigate;
  StreamSubscription<Uri>? _sub;

  /// Handle the cold-start link (if any), then subscribe to warm links.
  ///
  /// A duplicate delivery (some platforms replay the cold-start URI on the
  /// stream) is harmless: navigating to the location already on top is a
  /// no-op `go`. Safe to call once after the router is built.
  Future<void> start() async {
    final initial = await _source.initialLink();
    if (initial != null) handleLink(initial);
    _sub = _source.linkStream().listen(handleLink);
  }

  /// Parse one link through the JOIN grammar and navigate. Public for tests;
  /// production drives it via [start].
  void handleLink(Uri uri) {
    final target = parseJoinInput(uri.toString());
    _navigate(locationForJoinTarget(target));
  }

  /// Cancel the warm-link subscription. Call from the host widget's dispose.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
