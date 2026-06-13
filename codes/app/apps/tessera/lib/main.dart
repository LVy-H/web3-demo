import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app.dart';
import 'di/app_dependencies.dart';
import 'routing/deep_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The ONE production wiring — also pumped by the composition-root widget
  // test, so a provider missing here fails CI, not runtime.
  final dependencies = await AppDependencies.production();
  runApp(
    TesseraApp(
      dependencies: dependencies,
      // Real OS deep-link source — but ONLY off the web. On web, go_router
      // already owns the browser URL; app_links_web would surface the page URL
      // (e.g. /vote) as a "link", which the JOIN grammar doesn't match and
      // would route to /error on every normal load. Widget tests inject a fake.
      deepLinkSource: kIsWeb ? null : AppLinksSource(),
    ),
  );
}
