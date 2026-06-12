/// Local record of the polls THIS device joined — the data behind the VOTE
/// home's NEEDS YOU / WAITING / DONE sections.
///
/// Under the wallet-free model nothing on-chain links "this device" to "these
/// polls" (that is the point), so participation is a local record, written by
/// the port adapters when a join / lock-in / cast succeeds. Mirrors the
/// `CreatedPollsStore` pattern in core_storage; it lives here because the
/// record's shape (stage + receipt) is vote-space domain, not shared storage.
library;

// flutter_secure_storage reaches feature_vote ONLY through core_storage (a
// declared dependency whose production stores are built on it), so the
// resolution is pinned. feature_vote's pubspec is frozen by the R3
// file-ownership rule; declare the dependency directly when the freeze lifts.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How far this device's participation in a poll has progressed.
enum KnownPollStage {
  /// Joined (or asked to join) — the vote itself hasn't been cast here.
  joined,

  /// Blind poll: a choice is locked in, awaiting the confirmation window.
  committed,

  /// A ballot was cast (or a blind vote confirmed) from this device.
  voted,
}

/// One poll this device takes part in.
class KnownPoll {
  final String address;
  final String title;

  /// Registry module-type id (`anon-vote`, …). Used to pick the jargon-free
  /// kind label — never shown raw.
  final String moduleType;
  final KnownPollStage stage;
  final int joinedAtMs;

  /// The private vote receipt code (set when [stage] is voted, for proof
  /// modules).
  final String? receiptCode;

  /// The transaction reference for the receipt, when known.
  final String? receiptTx;

  const KnownPoll({
    required this.address,
    required this.title,
    required this.moduleType,
    required this.stage,
    required this.joinedAtMs,
    this.receiptCode,
    this.receiptTx,
  });

  KnownPoll copyWith({
    String? title,
    KnownPollStage? stage,
    String? receiptCode,
    String? receiptTx,
  }) => KnownPoll(
    address: address,
    title: title ?? this.title,
    moduleType: moduleType,
    stage: stage ?? this.stage,
    joinedAtMs: joinedAtMs,
    receiptCode: receiptCode ?? this.receiptCode,
    receiptTx: receiptTx ?? this.receiptTx,
  );

  Map<String, dynamic> toJson() => {
    'a': address,
    't': title,
    'm': moduleType,
    's': stage.name,
    'j': joinedAtMs,
    if (receiptCode != null) 'rc': receiptCode,
    if (receiptTx != null) 'rt': receiptTx,
  };

  static KnownPoll? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final address = raw['a'];
    if (address is! String || address.isEmpty) return null;
    return KnownPoll(
      address: address,
      title: raw['t'] is String ? raw['t'] as String : '',
      moduleType: raw['m'] is String ? raw['m'] as String : '',
      stage:
          KnownPollStage.values.asNameMap()[raw['s']] ?? KnownPollStage.joined,
      joinedAtMs: raw['j'] is int ? raw['j'] as int : 0,
      receiptCode: raw['rc'] is String ? raw['rc'] as String : null,
      receiptTx: raw['rt'] is String ? raw['rt'] as String : null,
    );
  }
}

/// The polls this device joined. Addresses are case-insensitive keys.
abstract class KnownPollsStore {
  /// All known polls, newest join first.
  Future<List<KnownPoll>> all();

  /// The record for [address], or null.
  Future<KnownPoll?> find(String address);

  /// Insert or update [poll] (matched by lowercased address). An update never
  /// regresses the stage (a `joined` write after `voted` keeps `voted`).
  Future<void> upsert(KnownPoll poll);
}

/// Production store backed by `flutter_secure_storage` (same posture as the
/// sibling core_storage stores: not secret, but no extra prefs dependency).
/// Read failures — including the no-platform-channel case in widget tests —
/// degrade to an empty list, never an exception into the UI.
class SecureKnownPollsStore implements KnownPollsStore {
  static const _key = 'tessera.known_polls';

  /// Hard ceiling on platform-channel waits: a hung secure-storage channel
  /// (it never completes under the widget-test binding, and can stall on
  /// broken keyrings) degrades to "no local record", never a stuck spinner.
  static const _channelTimeout = Duration(seconds: 3);

  final FlutterSecureStorage _s;

  SecureKnownPollsStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  @override
  Future<List<KnownPoll>> all() async {
    String? raw;
    try {
      raw = await _s.read(key: _key).timeout(_channelTimeout);
    } catch (_) {
      return const [];
    }
    return decodeKnownPolls(raw);
  }

  @override
  Future<KnownPoll?> find(String address) async {
    final key = address.toLowerCase();
    for (final p in await all()) {
      if (p.address.toLowerCase() == key) return p;
    }
    return null;
  }

  @override
  Future<void> upsert(KnownPoll poll) async {
    final merged = mergeKnownPoll(await all(), poll);
    try {
      await _s
          .write(key: _key, value: encodeKnownPolls(merged))
          .timeout(_channelTimeout);
    } catch (_) {
      // No secure storage on this platform/build: the record is best-effort
      // local memory, never a crash in the join/cast flow.
    }
  }
}

/// In-memory store for tests and previews (no platform channels).
class InMemoryKnownPollsStore implements KnownPollsStore {
  List<KnownPoll> _polls;

  InMemoryKnownPollsStore([Iterable<KnownPoll>? initial])
    : _polls = [...?initial];

  @override
  Future<List<KnownPoll>> all() async => List.unmodifiable(
    [..._polls]..sort((a, b) => b.joinedAtMs.compareTo(a.joinedAtMs)),
  );

  @override
  Future<KnownPoll?> find(String address) async {
    final key = address.toLowerCase();
    for (final p in _polls) {
      if (p.address.toLowerCase() == key) return p;
    }
    return null;
  }

  @override
  Future<void> upsert(KnownPoll poll) async {
    _polls = mergeKnownPoll(_polls, poll);
  }
}

/// Upsert [poll] into [existing] by lowercased address; stages only move
/// forward (joined → committed → voted).
List<KnownPoll> mergeKnownPoll(List<KnownPoll> existing, KnownPoll poll) {
  final key = poll.address.toLowerCase();
  final out = <KnownPoll>[];
  var replaced = false;
  for (final p in existing) {
    if (p.address.toLowerCase() != key) {
      out.add(p);
      continue;
    }
    replaced = true;
    final keepOldStage = p.stage.index > poll.stage.index;
    out.add(
      KnownPoll(
        address: p.address,
        title: poll.title.isNotEmpty ? poll.title : p.title,
        moduleType: poll.moduleType.isNotEmpty ? poll.moduleType : p.moduleType,
        stage: keepOldStage ? p.stage : poll.stage,
        joinedAtMs: p.joinedAtMs,
        receiptCode: poll.receiptCode ?? p.receiptCode,
        receiptTx: poll.receiptTx ?? p.receiptTx,
      ),
    );
  }
  if (!replaced) out.add(poll);
  out.sort((a, b) => b.joinedAtMs.compareTo(a.joinedAtMs));
  return out;
}

/// JSON list encode/decode, tolerant of corrupt entries (skipped, not thrown).
String encodeKnownPolls(List<KnownPoll> polls) =>
    jsonEncode([for (final p in polls) p.toJson()]);

List<KnownPoll> decodeKnownPolls(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [for (final entry in list) ?KnownPoll.fromJson(entry)];
  } catch (_) {
    return const [];
  }
}
