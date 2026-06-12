/// Production [BlindJourneyPort] over core_chain + core_crypto +
/// core_storage — the commit–reveal poll, driven by a local signer
/// ([ChainWriter]) because the blind module's writes are voter-addressed
/// (no relayer path exists for it yet).
library;

import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_crypto/crypto/blind_commit.dart';
import 'package:core_domain/journeys/blind_journey.dart';
import 'package:core_storage/blind_commit_store.dart';

import '../data/known_polls_store.dart';

class BlindPortAdapter implements BlindJourneyPort {
  final ChainReader reader;
  final ChainWriter writer;
  final BlindCommitStore commitStore;
  final String pollAddress;

  /// Bare ABI array (or hardhat artifact) JSON for ZkBlindVoting — injected
  /// by the app shell from core_chain's packaged assets.
  final String blindAbiJson;

  /// Best-effort local participation record; failures never surface.
  final KnownPollsStore? knownPolls;
  final String pollTitle;

  static const _abiName = 'ZkBlindVoting';

  BlindPortAdapter({
    required this.reader,
    required this.writer,
    required this.commitStore,
    required this.pollAddress,
    required this.blindAbiJson,
    this.knownPolls,
    this.pollTitle = '',
  });

  @override
  Future<BlindJourneySnapshot> fetchState() async {
    final phase = await reader.getState(pollAddress);
    final finalized = await reader.isFinalized(pollAddress);
    final voter = writer.signerAddress;
    if (voter == null) {
      return BlindJourneySnapshot(
        phase: phase,
        registered: false,
        committed: false,
        revealed: false,
        finalized: finalized,
      );
    }
    return BlindJourneySnapshot(
      phase: phase,
      registered: await reader.isRegistered(pollAddress, voter),
      committed: await reader.hasVoted(pollAddress, voter),
      revealed: await reader.hasRevealed(pollAddress, voter),
      finalized: finalized,
    );
  }

  @override
  Future<void> register() async {
    await writer.send(
      to: pollAddress,
      abiJson: blindAbiJson,
      abiName: _abiName,
      function: 'register',
    );
    await _record(KnownPollStage.joined);
  }

  @override
  Future<SaltReceipt> commit(int optionIndex) async {
    final salt = generateSalt();
    final hash = blindCommitHash(optionIndex, salt);
    final saltHex = toHex0x(salt);
    // Persist BEFORE the send: if the tx lands but the app dies between the
    // two, the salt must already be recoverable on this device.
    await commitStore.save(pollAddress, SavedCommit(optionIndex, saltHex));
    await writer.send(
      to: pollAddress,
      abiJson: blindAbiJson,
      abiName: _abiName,
      function: 'commitVote',
      params: [hash],
    );
    await _record(KnownPollStage.committed);
    return SaltReceipt(optionIndex: optionIndex, saltHex: saltHex);
  }

  @override
  Future<bool> hasSalt() async => (await commitStore.read(pollAddress)) != null;

  @override
  Future<void> reveal() async {
    final saved = await commitStore.read(pollAddress);
    if (saved == null) {
      throw StateError('no vote key on this device for $pollAddress');
    }
    await writer.send(
      to: pollAddress,
      abiJson: blindAbiJson,
      abiName: _abiName,
      function: 'revealVote',
      params: [BigInt.from(saved.optionIndex), fromHex(saved.saltHex)],
    );
    await _record(KnownPollStage.voted);
  }

  @override
  Future<DateTime> fetchRevealDeadline() async {
    final seconds = await reader.getRevealDeadline(pollAddress);
    return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
  }

  Future<void> _record(KnownPollStage stage) async {
    final store = knownPolls;
    if (store == null) return;
    try {
      await store.upsert(
        KnownPoll(
          address: pollAddress,
          title: pollTitle,
          moduleType: 'blind-vote',
          stage: stage,
          joinedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // Local bookkeeping only.
    }
  }
}
