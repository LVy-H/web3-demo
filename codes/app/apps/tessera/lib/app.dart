/// The Tessera app widget: production providers + guarded router. Kept
/// separate from main() so widget tests pump the REAL composition.
library;

import 'dart:async';

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'di/app_dependencies.dart';
import 'routing/router.dart';

class TesseraApp extends StatefulWidget {
  final AppDependencies dependencies;

  /// Test seam for deep-link smoke tests; production uses the default.
  final String initialLocation;

  const TesseraApp({
    super.key,
    required this.dependencies,
    this.initialLocation = '/vote',
  });

  @override
  State<TesseraApp> createState() => _TesseraAppState();
}

class _TesseraAppState extends State<TesseraApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildTesseraRouter(
      appState: widget.dependencies.appState,
      pollModuleResolver: widget.dependencies.pollModuleResolver,
      initialLocation: widget.initialLocation,
    );
    // Async probes (relayer reachability, identity presence). Capabilities
    // from the synchronous platform probe are already in place, so guards
    // are correct for the first frame; these refine and re-trigger redirects
    // via refreshListenable.
    unawaited(widget.dependencies.appState.start());
  }

  @override
  void dispose() {
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
