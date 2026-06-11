/// Tessera JOIN — the universal-entry grammar (spec §4.1).
///
/// Pure Dart, UI-free: turns any scanned / pasted / typed value into a typed
/// [JoinTarget]. Screens and the JoinTarget→route mapping arrive with the R3
/// shell; this package is the part that must always be correct.
library;

export 'src/join_grammar.dart'
    show parseJoinInput, shareLinkForPoll, tryParseJoinCode;
export 'src/join_target.dart';
