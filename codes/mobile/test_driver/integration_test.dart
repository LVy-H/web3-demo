// Driver entrypoint for `flutter drive` (optional; enables screenshots and
// running the integration_test suite via the driver protocol). The primary
// runner is `flutter test integration_test/...` (see dev-stack.sh e2e); this
// file is here for `flutter drive --driver=test_driver/integration_test.dart
// --target=integration_test/app_test.dart`.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
