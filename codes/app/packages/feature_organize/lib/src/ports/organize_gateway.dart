/// The relayer wire calls the ORGANIZE space needs BEYOND what the lifted
/// pre-R4 [RelayClient] exposes. PR #108's relayer accepts the optional R4
/// `visibility` / `resultsPolicy` fields on create-poll (omitted = the
/// private defaults) and exposes the sponsored `start-voting` lifecycle
/// route; neither is reachable through `core_relay`'s typed client, and the
/// R3 fan-out freezes the core packages. The app shell implements this
/// gateway over its own HTTP client; widget tests fake it.
library;

import 'package:core_relay/relay_client.dart' show CreatePollResult;

/// Raised by gateway implementations with ORGANIZER-FACING copy — the
/// message is shown verbatim in error states, so it must stay jargon-free.
class OrganizeWireException implements Exception {
  final String message;

  const OrganizeWireException(this.message);

  @override
  String toString() => message;
}

/// Sponsored lifecycle calls against the relayer (spec §4.3: sponsored is
/// THE path, not a fallback).
abstract interface class OrganizeRelayGateway {
  /// `POST /api/relay/create-poll` with the R4 policy fields. [initDataHex]
  /// is the module's PRE-R4 `initialize(...)` calldata — the relayer shims
  /// the trailing `resultsPolicy` argument server-side (#108), so clients
  /// MUST NOT re-encode initialize themselves. [visibility] and
  /// [resultsPolicy] are `0|1` per the relayer contract; 0/0 are the
  /// private-by-default values.
  Future<CreatePollResult> createPoll({
    required String moduleType,
    required String title,
    required String description,
    required String initDataHex,
    required int visibility,
    required int resultsPolicy,
  });

  /// `POST /api/relay/start-voting` — the relayer (owner of sponsored
  /// polls) opens the voting phase. Throws [OrganizeWireException] with the
  /// relayer's client-facing message on failure.
  Future<void> startVoting(String pollAddress);

  /// Close the voting phase. The deployed relayer does not expose this
  /// route yet; implementations must surface that honestly (a friendly
  /// [OrganizeWireException], never a raw 404).
  Future<void> endVoting(String pollAddress);
}
