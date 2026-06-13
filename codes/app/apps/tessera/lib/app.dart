/// The Tessera app widget: production providers + guarded router. Kept
/// separate from main() so widget tests pump the REAL composition.
library;

import 'dart:async';

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'di/app_dependencies.dart';
import 'routing/deep_link_service.dart';
import 'routing/router.dart';

class TesseraApp extends StatefulWidget {
  final AppDependencies dependencies;

  /// Test seam for deep-link smoke tests; production uses the default.
  final String initialLocation;

  /// OS deep-link source. Production (`main`) passes an [AppLinksSource];
  /// widget tests pass a fake to drive links, or omit it to leave deep linking
  /// off (no platform channel is touched under test).
  final DeepLinkSource? deepLinkSource;

  const TesseraApp({
    super.key,
    required this.dependencies,
    this.initialLocation = '/vote',
    this.deepLinkSource,
  });

  @override
  State<TesseraApp> createState() => _TesseraAppState();
}

class _TesseraAppState extends State<TesseraApp> {
  late final GoRouter _router;
  DeepLinkService? _deepLinks;

  @override
  void initState() {
    super.initState();
    _router = buildTesseraRouter(
      appState: widget.dependencies.appState,
      pollModuleResolver: widget.dependencies.pollModuleResolver,
      initialLocation: widget.initialLocation,
    );
    // OS deep links (tessera://…) → router. Started after the router exists so
    // a cold-start link lands on a live navigator. Disabled when no source is
    // injected (the default in widget tests that don't exercise deep linking).
    final deepLinkSource = widget.deepLinkSource;
    if (deepLinkSource != null) {
      _deepLinks = DeepLinkService(
        source: deepLinkSource,
        navigate: _router.go,
      );
      unawaited(_deepLinks!.start());
    }
    // Async probes (relayer reachability, identity presence). Capabilities
    // from the synchronous platform probe are already in place, so guards
    // are correct for the first frame; these refine and re-trigger redirects
    // via refreshListenable.
    unawaited(widget.dependencies.appState.start());
  }

  @override
  void dispose() {
    unawaited(_deepLinks?.dispose());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: buildAppProviders(widget.dependencies),
    child: MaterialApp.router(
      title: 'Tessera',
      debugShowCheckedModeBanner: false,
      theme: buildDarkBauhausTheme(),
      routerConfig: _router,
    ),
  );
}
