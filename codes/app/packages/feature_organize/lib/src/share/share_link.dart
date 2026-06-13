/// The real OS share-sheet call behind [DistributeSheet]'s injectable
/// [ShareLinkFn]. Kept in its own file so the widget never imports the
/// platform plugin directly — widget tests pass a spy instead (the plugin's
/// method channel has no binding under `flutter test`).
library;

import 'package:share_plus/share_plus.dart';

/// Injectable share action: hand it the honest share text, it summons the
/// platform share sheet.
typedef ShareLinkFn = Future<void> Function(String text);

/// Default [ShareLinkFn]: opens the OS share sheet with [text].
///
/// share_plus 12 exposes `SharePlus.instance.share(ShareParams(...))`
/// (the older static `Share.share(text)` is deprecated).
Future<void> shareTextViaOs(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
