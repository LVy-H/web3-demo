import '../../core/crypto/blind_commit.dart';
import '../models/blind_snapshot.dart';
import '../services/blind_commit_store.dart';
import '../services/chain_reader.dart';
import '../services/chain_writer.dart';

/// Drives the M2 commit-reveal lifecycle: reads the poll + this signer's status,
/// and (when a dev-signer is configured) sends register / commit / reveal and the
/// owner's startVoting / endVoting / finalize transactions. The commit salt is
/// generated here and stashed in [BlindCommitStore] so reveal can recover it.
class BlindRepository {
  final ChainReader reader;
  final ChainWriter writer;
  final BlindCommitStore commits;
  final String blindAbiJson;

  BlindRepository({
    required this.reader,
    required this.writer,
    required this.commits,
    required this.blindAbiJson,
  });

  static const _name = 'ZkBlindVoting';

  bool get canWrite => writer.canSign;
  String? get signer => writer.signerAddress;

  Future<BlindSnapshot> fetch(String poll) async {
    final voter = writer.signerAddress;
    final state = await reader.getState(poll);
    final options = await reader.getOptions(poll);
    final results = await reader.getResults(poll);
    final participantCount = await reader.getParticipantCount(poll);
    final owner = await reader.getOwner(poll);
    final revealDeadline = await reader.getRevealDeadline(poll);
    final finalized = await reader.isFinalized(poll);

    var registered = false, committed = false, revealed = false;
    if (voter != null) {
      registered = await reader.isRegistered(poll, voter);
      committed = await reader.hasVoted(poll, voter);
      revealed = await reader.hasRevealed(poll, voter);
    }

    return BlindSnapshot(
      address: poll,
      state: state,
      options: options,
      results: results,
      participantCount: participantCount,
      owner: owner,
      revealDeadline: revealDeadline,
      finalized: finalized,
      registered: registered,
      committed: committed,
      revealed: revealed,
    );
  }

  Future<String> _send(String poll, String fn, [List<dynamic> params = const []]) =>
      writer.send(
          to: poll,
          abiJson: blindAbiJson,
          abiName: _name,
          function: fn,
          params: params);

  // ── Voter ──
  Future<String> register(String poll) => _send(poll, 'register');

  /// Commit [optionIndex]: generate a salt, stash {option, salt} locally, send
  /// the hash. The salt never leaves the device until reveal.
  Future<String> commit(String poll, int optionIndex) async {
    final salt = generateSalt();
    final hash = blindCommitHash(optionIndex, salt);
    await commits.save(poll, SavedCommit(optionIndex, toHex0x(salt)));
    return _send(poll, 'commitVote', [hash]);
  }

  /// Reveal the vote committed on this device. Throws if no commit is stored.
  Future<String> reveal(String poll) async {
    final saved = await commits.read(poll);
    if (saved == null) {
      throw StateError('No saved commit on this device for $poll');
    }
    final hash = await _send(poll, 'revealVote',
        [BigInt.from(saved.optionIndex), fromHex(saved.saltHex)]);
    // The salt's only purpose was this reveal; don't retain the vote secret.
    await commits.clear(poll);
    return hash;
  }

  Future<bool> hasSavedCommit(String poll) async =>
      (await commits.read(poll)) != null;

  // ── Owner ──
  Future<String> startVoting(String poll) => _send(poll, 'startVoting');
  Future<String> endVoting(String poll) => _send(poll, 'endVoting');
  Future<String> finalize(String poll) => _send(poll, 'finalizeResults');
}
