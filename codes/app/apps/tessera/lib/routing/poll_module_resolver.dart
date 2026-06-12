/// On-chain module resolution for the single `/poll/:address` route
/// (R2f deliverable 2 — kills the legacy "card tap shows wrong screen" class
/// at the root: the module type comes from the registry, never from a
/// `?module=` query hint).
///
/// Thin adapter over core_chain's reader: inject `reader.getAllPolls` in
/// production, a fake in tests. Total function — unknown addresses and
/// unreachable RPC come back as typed values, never as thrown errors.
library;

import 'package:core_domain/models/poll_info.dart';

/// Result of resolving a poll address to its registry record.
sealed class PollModuleResolution {
  const PollModuleResolution();
}

/// The address is a registered poll; [moduleType] is the on-chain truth.
final class PollModuleResolved extends PollModuleResolution {
  final PollInfo info;

  const PollModuleResolved(this.info);

  String get moduleType => info.moduleType;

  @override
  String toString() => 'PollModuleResolved(${info.pollAddress}, $moduleType)';
}

/// The registry answered, but no poll with this address exists there (or the
/// address is not even address-shaped). Not retryable.
final class PollUnknown extends PollModuleResolution {
  final String address;

  const PollUnknown(this.address);

  String get messageKey => 'error.poll.unknown';

  @override
  String toString() => 'PollUnknown($address)';
}

/// The registry could not be reached (RPC down, timeout, decode failure).
/// Retryable — the poll screen offers a retry, not a crash.
final class PollLookupFailed extends PollModuleResolution {
  final String address;
  final Object cause;

  const PollLookupFailed(this.address, this.cause);

  String get messageKey => 'error.poll.unreachable';

  @override
  String toString() => 'PollLookupFailed($address, cause: $cause)';
}

final RegExp _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

class PollModuleResolver {
  /// Fetches the registry directory (production: `ChainReader.getAllPolls`,
  /// which includes unlisted polls — link-access still resolves them).
  final Future<List<PollInfo>> Function() fetchPolls;

  /// Successful resolutions cached per (lowercased) address: a poll's module
  /// type is immutable on-chain, so one lookup per address per app run.
  /// Failures are NOT cached — a later retry or a newly created poll must be
  /// able to succeed.
  final Map<String, PollModuleResolved> _cache = {};

  PollModuleResolver({required this.fetchPolls});

  Future<PollModuleResolution> resolve(String address) async {
    if (!_addressPattern.hasMatch(address)) return PollUnknown(address);
    final key = address.toLowerCase();
    final cached = _cache[key];
    if (cached != null) return cached;

    final List<PollInfo> polls;
    try {
      polls = await fetchPolls();
    } catch (cause) {
      return PollLookupFailed(address, cause);
    }

    for (final info in polls) {
      if (info.pollAddress.toLowerCase() == key) {
        final resolved = PollModuleResolved(info);
        _cache[key] = resolved;
        return resolved;
      }
    }
    return PollUnknown(address);
  }
}
