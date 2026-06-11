import 'package:flutter/material.dart';

import 'app.dart';
import 'di/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The ONE production wiring — also pumped by the composition-root widget
  // test, so a provider missing here fails CI, not runtime.
  final dependencies = await AppDependencies.production();
  runApp(TesseraApp(dependencies: dependencies));
}
