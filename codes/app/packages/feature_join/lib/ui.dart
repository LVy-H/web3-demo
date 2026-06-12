/// Tessera JOIN — the Flutter surface (R3).
///
/// Library split, on purpose: `package:feature_join/feature_join.dart`
/// stays the pure-Dart grammar and `live.dart` the pure-Dart port adapter
/// (both importable, and `dart test`-able, without Flutter); THIS export
/// carries the widgets. Nothing here re-exports the other two — import
/// what you need.
library;

export 'src/ui/join_code_notice.dart';
export 'src/ui/join_surface.dart';
export 'src/ui/live_voter_flow.dart';
export 'src/ui/qr_scan_sheet.dart';
