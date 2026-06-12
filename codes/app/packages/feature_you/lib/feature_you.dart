/// Tessera YOU space (R3): voting pass, receipts archive, verify-anything
/// and settings (spec §3–§4). Pure feature widgets + controllers — the app
/// shell injects stores, AppState hooks and navigation as plain callbacks.
library;

export 'src/pass/voting_pass_controller.dart';
export 'src/pass/voting_pass_section.dart';
export 'src/receipts/receipts_section.dart';
export 'src/receipts/receipts_store.dart';
export 'src/receipts/vote_receipt.dart';
export 'src/settings/about_screen.dart';
export 'src/settings/diagnostics_screen.dart';
export 'src/settings/network_settings_screen.dart';
export 'src/settings/settings_section.dart';
export 'src/verify/verify_controller.dart';
export 'src/verify/verify_view.dart';
export 'src/you_space_view.dart';

/// Kept for the R3 scaffold's workspace smoke test.
const String featureYouPackageName = 'feature_you';
