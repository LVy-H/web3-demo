// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkSurveyVoting}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount, InvalidInitialization, etc.)
///      cover access-control / lifecycle reverts; these are the module's local
///      errors. The first block is reused verbatim from the sibling modules
///      (ZkApprovalVoting / ZkQuadraticVoting); the last three are survey-local.
error NotInRegistration();
error NotInVoting();
error CanOnlyStartFromRegistration();
error NeedAtLeastTwoOptions();
error NeedAtLeastOneVoter();
error TooManyOptions();
error EmptyBatch();
error BatchTooLarge();
error AlreadyRegistered();
error DuplicateInBatch();
error AlreadyVoted();
error InvalidScope();
error TamperedVoteSignal();
error InvalidProof();
// ── Survey-local ────────────────────────────────────────────────────────
error NoQuestions();
error TooManyQuestions();
error WrongQuestionCount();
error InvalidAnswer();

/// @title ZkSurveyVoting (Phase 12d)
/// @notice Multi-question ("Google-Forms") survey module implementing IZkPoll. A
///         structural sibling of M3 ZkApprovalVoting / QV ZkQuadraticVoting:
///         identical Semaphore membership / registration / nullifier model and
///         the same relayer-submitted anonymity. The difference is the ballot —
///         it generalizes "one poll = one question" to "one survey = an ordered
///         list of questions", while keeping the anonymity model identical: ONE
///         ballot, ONE Semaphore proof, ONE nullifier per voter per survey ⇒ one
///         submission per voter covering every question.
///
///         A survey is an ordered Question[]. Each question has a type and its
///         OWN option list and OWN tally. v1 question types:
///           - SingleChoice — pick exactly one option (the M1 encoding: an option
///             index); answers[q] = the chosen index.
///           - MultiSelect  — approve any NON-EMPTY subset (the M3 encoding: a
///             bitmask, bit i ⇒ option i); answers[q] = the bitmask.
///         The encoding is deliberately extensible to rating / ranked / quadratic
///         per-question types later — each is a single ≤32-bit word that slots
///         into the same uint256[] answer vector with NO change to the commitment
///         scheme; only the per-question validation switch (_validateAnswer)
///         grows. v1 ships SingleChoice + MultiSelect only.
///
///         BALLOT BINDING (hash commitment). The voter submits the FULL answer
///         vector in calldata plus one proof. The client computes
///             message = keccak256(abi.encode(answers)) >> 8
///         before proving and binds it to the single Semaphore `message`; the
///         contract RECOMPUTES that value from calldata and requires
///         `proof.message == recomputed`. This is non-malleable (nobody, not even
///         the relayer, can re-weight an answer without invalidating the SNARK)
///         and supports any survey size and any mix of question types. The
///         serialization is canonical `abi.encode(uint256[])` — offset + length +
///         words — NOT abi.encodePacked, so the on-chain recompute matches the
///         off-chain ethers `AbiCoder.encode(['uint256[]'], [answers])` /
///         pointycastle byte-for-byte (the load-bearing cross-impl gate).
///
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy
///         compatibility.
contract ZkSurveyVoting is IZkPoll, Initializable, Ownable {
    /// @notice v1 question types. Extend (Rating, Ranked, Quadratic) later — each
    ///         is a single ≤32-bit word in the same answer vector.
    enum QType {
        SingleChoice,
        MultiSelect
    }

    /// @notice One survey question: its type + its own on-chain option labels. The
    ///         per-option tally is held separately in `voteCounts` (a mapping
    ///         cannot live inside a memory-returned struct).
    struct Question {
        QType qType;
        string[] options;
    }

    /// @notice Max number of options PER QUESTION. Matches M3's approval cap: a
    ///         MultiSelect bitmask over ≤32 options fits one word, and
    ///         `1 << optionCount` never overflows a uint256. Enforced at
    ///         initialize() for every question.
    uint256 public constant MAX_OPTIONS = 32;

    /// @notice Max number of questions PER SURVEY. Bounds {castVote} gas so a
    ///         creator can never initialize a survey too large to vote on.
    /// @dev Gas reasoning. The worst case is the FIRST voter on a maximal survey
    ///      of MAX_QUESTIONS MultiSelect questions, each with MAX_OPTIONS (32)
    ///      options, voting the full-width mask: the tally does
    ///      MAX_QUESTIONS × MAX_OPTIONS fresh SSTOREs (0→nonzero, ≈ 20k–22k gas
    ///      each). At 16 questions that is 16 × 32 ≈ 512 fresh SSTOREs ≈ 11–12M
    ///      gas; adding the nullifier SSTORE, keccak over the answer vector, the
    ///      Semaphore Groth16 verify (~300k) and the SurveyVoteCast log keeps the
    ///      worst-case castVote around ~12M — well under the ~30M block gas limit
    ///      (≈40% of a block), with headroom for future per-question types. A cap
    ///      of 32 would push the tally alone to 32 × 32 ≈ 1024 fresh SSTOREs
    ///      ≈ 22–23M gas, dangerously close to the block limit, so 16 is chosen.
    ///      Enforced at initialize() against the decoded question count.
    uint256 public constant MAX_QUESTIONS = 16;

    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;

    /// @notice The ordered survey questions, fixed at initialize().
    Question[] internal questions;

    /// @notice Per-question, per-option tally: voteCounts[q][option] => count.
    mapping(uint256 => mapping(uint256 => uint256)) internal voteCounts;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;

    uint256 public participantCount;

    event VoterRegistered(uint256 identityCommitment);
    /// @notice The FULL answer vector, on-chain for auditability (the answer
    ///         content is public — the survey hides WHO answered, not WHAT).
    event SurveyVoteCast(uint256[] answers);
    event PollClosed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initialize the clone (replaces constructor).
    /// @param _semaphoreAddress  Address of the Semaphore contract
    /// @param _owner             Survey owner / admin
    /// @param initData           ABI-encoded `(QType qType, string[] options)[]`
    ///                           — i.e. `abi.encode(Question[])`. Decoded into the
    ///                           ordered question list. Validated: ≥1 question
    ///                           (else NoQuestions) and ≤ MAX_QUESTIONS (else
    ///                           TooManyQuestions); each question ≥2 options
    ///                           (else NeedAtLeastTwoOptions) and ≤ MAX_OPTIONS
    ///                           (else TooManyOptions).
    function initialize(
        address _semaphoreAddress,
        address _owner,
        bytes calldata initData
    ) external initializer {
        Question[] memory qs = abi.decode(initData, (Question[]));
        if (qs.length == 0) revert NoQuestions();
        if (qs.length > MAX_QUESTIONS) revert TooManyQuestions();

        for (uint256 q = 0; q < qs.length; q++) {
            uint256 n = qs[q].options.length;
            if (n < 2) revert NeedAtLeastTwoOptions();
            if (n > MAX_OPTIONS) revert TooManyOptions();
            // Deep copy memory -> storage.
            questions.push(qs[q]);
        }

        semaphore = ISemaphore(_semaphoreAddress);
        _transferOwnership(_owner);
        state = PollState.Registration;

        groupId = semaphore.createGroup(address(this));
    }

    // ── IZkPoll views ───────────────────────────────────────────────

    /// @dev Resolves diamond inheritance between IZkPoll.owner() and Ownable.owner().
    function owner() public view override(IZkPoll, Ownable) returns (address) {
        return Ownable.owner();
    }

    function getState() external view override returns (PollState) {
        return state;
    }

    /// @notice IZkPoll compliance — DOCUMENTED DEGENERATE: returns QUESTION 0's
    ///         per-option tally so a generic IZkPoll consumer (e.g. the registry's
    ///         flat reads) never reverts. The AUTHORITATIVE survey surface is
    ///         {getSurveyResults} / {getQuestionResults}; a survey-aware consumer
    ///         must use those.
    function getResults() external view override returns (uint256[] memory) {
        return getQuestionResults(0);
    }

    /// @notice IZkPoll compliance — DOCUMENTED DEGENERATE: returns QUESTION 0's
    ///         option labels (see {getResults}). Use {getQuestionOptions} for any
    ///         other question.
    function getOptions() external view override returns (string[] memory) {
        return getQuestionOptions(0);
    }

    function getParticipantCount() external view override returns (uint256) {
        return participantCount;
    }

    function verifyParticipation(uint256 nullifierHash) external view override returns (bool) {
        return isNullifierUsed[nullifierHash];
    }

    // ── Survey-specific views (the AUTHORITATIVE results surface) ────

    /// @notice Number of questions in the survey.
    function getQuestionCount() external view returns (uint256) {
        return questions.length;
    }

    /// @notice Question `q`'s per-option tally: [option] => count. For a
    ///         MultiSelect question the counts are approvals (their sum can exceed
    ///         the voter count); for SingleChoice they are exclusive votes.
    /// @dev `public` (not `external`) so {getResults} and {getSurveyResults} can
    ///      call it internally.
    function getQuestionResults(uint256 q) public view returns (uint256[] memory) {
        uint256 n = questions[q].options.length;
        uint256[] memory results = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            results[i] = voteCounts[q][i];
        }
        return results;
    }

    /// @notice The full survey tally: [q][option] => count, one inner array per
    ///         question. This is what the Flutter side renders as N ResultsBars.
    function getSurveyResults() external view returns (uint256[][] memory) {
        uint256 qn = questions.length;
        uint256[][] memory all = new uint256[][](qn);
        for (uint256 q = 0; q < qn; q++) {
            all[q] = getQuestionResults(q);
        }
        return all;
    }

    /// @notice Question `q`'s own option labels.
    /// @dev `public` (not `external`) so {getOptions} can call it internally.
    function getQuestionOptions(uint256 q) public view returns (string[] memory) {
        return questions[q].options;
    }

    /// @notice Question `q`'s type (SingleChoice or MultiSelect).
    function getQuestionType(uint256 q) external view returns (QType) {
        return questions[q].qType;
    }

    // ── Admin: Register Voters ──────────────────────────────────────

    function registerVoter(uint256 identityCommitment) external onlyOwner {
        if (state != PollState.Registration) revert NotInRegistration();
        if (registeredCommitments[identityCommitment]) revert AlreadyRegistered();

        registeredCommitments[identityCommitment] = true;
        participantCount++;
        semaphore.addMember(groupId, identityCommitment);

        emit VoterRegistered(identityCommitment);
    }

    function registerVoters(uint256[] calldata identityCommitments) external onlyOwner {
        if (state != PollState.Registration) revert NotInRegistration();
        if (identityCommitments.length == 0) revert EmptyBatch();
        if (identityCommitments.length > 100) revert BatchTooLarge();

        for (uint256 i = 0; i < identityCommitments.length; i++) {
            if (registeredCommitments[identityCommitments[i]]) revert DuplicateInBatch();
            registeredCommitments[identityCommitments[i]] = true;
            participantCount++;
            semaphore.addMember(groupId, identityCommitments[i]);
            emit VoterRegistered(identityCommitments[i]);
        }
    }

    // ── Admin: Poll Lifecycle ───────────────────────────────────────

    /// @notice Start the voting phase. Unlike the single-question siblings there
    ///         is no flat `options` array to check — per-question option-count
    ///         validation (≥2, ≤MAX_OPTIONS) and the ≥1-question rule are enforced
    ///         in {initialize}, so a survey clone always has ≥1 well-formed
    ///         question by the time it exists. The only runtime gate is ≥1 voter.
    function startVoting() external onlyOwner {
        if (state != PollState.Registration) revert CanOnlyStartFromRegistration();
        if (participantCount < 1) revert NeedAtLeastOneVoter();
        state = PollState.Voting;
        emit StateChanged(PollState.Voting);
    }

    function endVoting() external onlyOwner {
        if (state != PollState.Voting) revert NotInVoting();
        state = PollState.Ended;
        emit StateChanged(PollState.Ended);
        emit PollClosed();
    }

    // ── Ballot validation ───────────────────────────────────────────
    //
    // Per-question, by type. Reverts InvalidAnswer on the first malformed answer.
    // This is `view` and is called for every question BEFORE the nullifier write,
    // so a malformed ballot is always retryable (no lockout).
    //
    //   - SingleChoice: answers[q] is an option index; valid iff
    //     `< options.length` (an out-of-range index reverts).
    //   - MultiSelect:  answers[q] is a bitmask; valid iff NON-EMPTY (`!= 0`) AND
    //     no out-of-range/high bits (`< (1 << options.length)`). This mirrors M3's
    //     `bitmask >= (1 << options.length)` high-bit guard and its no-empty rule.
    //     options.length ≤ MAX_OPTIONS (32) so `1 << options.length` never
    //     overflows a uint256.
    function _validateAnswer(uint256 q, uint256 answer) internal view {
        Question storage question = questions[q];
        uint256 n = question.options.length;
        if (question.qType == QType.SingleChoice) {
            if (answer >= n) revert InvalidAnswer();
        } else {
            // MultiSelect
            if (answer == 0) revert InvalidAnswer(); // no empty ballot
            if (answer >= (1 << n)) revert InvalidAnswer(); // no out-of-range/high bits
        }
    }

    // ── Voter: Cast an anonymous SURVEY ballot using Semaphore ───────
    //
    // The voter submits the FULL answer vector (one word per question, in question
    // order) plus one proof. Every reject-check below runs in the spec's numbered
    // order and BEFORE isNullifierUsed is set, so a rejected ballot never consumes
    // the nullifier — the voter can retry with a valid ballot using the same
    // identity (same nullifier). This is the identical no-lockout discipline of
    // M1/M2/M3/QV. The commitment recompute (check 4) binds the ENTIRE answer
    // vector to the proof.
    function castVote(
        uint256[] calldata answers,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        // 1. Must be in the Voting phase.
        if (state != PollState.Voting) revert NotInVoting();

        // 2. One answer per question, in question order.
        uint256 qn = questions.length;
        if (answers.length != qn) revert WrongQuestionCount();

        // 3. Per-question validation by type (reverts InvalidAnswer on the first
        //    malformed answer — all before the nullifier write).
        for (uint256 q = 0; q < qn; q++) {
            _validateAnswer(q, answers[q]);
        }

        // 4. Commitment recompute — bind the whole vector to the proof. Canonical
        //    abi.encode(uint256[]) (offset+length+words), reduced by >> 8 exactly
        //    like Semaphore's bundled hash() helper. Matches the off-chain
        //    ethers `AbiCoder.encode(['uint256[]'], [answers])` byte-for-byte.
        uint256 recomputed = uint256(keccak256(abi.encode(answers))) >> 8;
        if (proof.message != recomputed) revert TamperedVoteSignal();

        // 5. One ballot per nullifier (single-use).
        if (isNullifierUsed[proof.nullifier]) revert AlreadyVoted();

        // 6. Scope must bind to THIS survey (one nullifier per voter per survey).
        if (proof.scope != uint256(uint160(address(this)))) revert InvalidScope();

        // 7. The Semaphore membership proof must verify.
        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidProof();

        // All checks passed — consume the nullifier, then tally per question.
        isNullifierUsed[proof.nullifier] = true;

        for (uint256 q = 0; q < qn; q++) {
            if (questions[q].qType == QType.SingleChoice) {
                // Exactly one option (the chosen index; validated < options.length).
                voteCounts[q][answers[q]]++;
            } else {
                // MultiSelect — increment every set bit (every approved option).
                uint256 m = answers[q];
                uint256 n = questions[q].options.length;
                for (uint256 i = 0; i < n; i++) {
                    if ((m >> i) & 1 == 1) voteCounts[q][i]++;
                }
            }
        }

        emit SurveyVoteCast(answers);
    }
}
