import '../services/chain_reader.dart';

/// Receipt verification reads (kept separate from [PollRepository] so it stays
/// focused). Checks whether a nullifier has voted in a poll — proves
/// participation without revealing the option.
abstract class VerifyRepository {
  Future<bool> isNullifierUsed(String pollAddress, String nullifier);
}

class ChainVerifyRepository implements VerifyRepository {
  final ChainReader reader;
  const ChainVerifyRepository(this.reader);

  @override
  Future<bool> isNullifierUsed(String pollAddress, String nullifier) =>
      reader.isNullifierUsed(pollAddress, nullifier);
}
