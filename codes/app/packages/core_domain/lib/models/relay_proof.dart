/// Semaphore proof payload as the relayer's `POST /api/relay/vote` expects it.
///
/// Mirrors the body built in `codes/frontend/src/hooks/useRelay.ts`: numeric
/// field elements are decimal strings (snarkjs emits stringified field
/// elements), and `merkleTreeDepth` is a plain number. The relayer
/// (`relay.ts toProofStruct`) re-parses each with `BigInt(...)`.
class RelayProof {
  final int merkleTreeDepth;
  final String merkleTreeRoot;
  final String nullifier;
  final String message;
  final String scope;
  final List<String> points;

  const RelayProof({
    required this.merkleTreeDepth,
    required this.merkleTreeRoot,
    required this.nullifier,
    required this.message,
    required this.scope,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
    'merkleTreeDepth': merkleTreeDepth,
    'merkleTreeRoot': merkleTreeRoot,
    'nullifier': nullifier,
    'message': message,
    'scope': scope,
    'points': points,
  };

  factory RelayProof.fromJson(Map<String, dynamic> j) => RelayProof(
    merkleTreeDepth: (j['merkleTreeDepth'] as num).toInt(),
    merkleTreeRoot: j['merkleTreeRoot'].toString(),
    nullifier: j['nullifier'].toString(),
    message: j['message'].toString(),
    scope: j['scope'].toString(),
    points: (j['points'] as List).map((e) => e.toString()).toList(),
  );
}
