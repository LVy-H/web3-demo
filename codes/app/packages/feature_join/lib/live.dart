/// Tessera JOIN — the live-voter effect boundary (R3).
///
/// Pure Dart, like the grammar export: [RelayLiveVoterPort] implements
/// core_domain's `LiveVoterPort` over the relayer + injected chain reads,
/// with no Flutter anywhere in its import graph — so it runs under plain
/// `dart test` next to the grammar suite. Widgets live in `ui.dart`.
library;

export 'src/live/relay_live_voter_port.dart';
