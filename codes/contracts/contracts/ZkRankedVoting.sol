// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkRankedVoting}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount, InvalidInitialization, etc.)
///      cover access-control / lifecycle reverts; these are the module's local errors.
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
error EmptyBallot();
error InvalidBallot();
error AlreadyVoted();
error InvalidScope();
error TamperedVoteSignal();
error InvalidProof();

/// @title ZkRankedVoting (Phase 12b)
/// @notice Ranked-choice / instant-runoff (IRV) voting module implementing
///         IZkPoll. A structural sibling of M3 ZkApprovalVoting: identical
///         Semaphore membership / registration / nullifier model and
///         relayer-submitted anonymity. The differences are exactly two:
///
///         1. The ballot is a PACKED RANKING in the Semaphore `message` field —
///            up to MAX_OPTIONS (8) rank slots of 4 bits each (≤32 bits total).
///            Slot value 0 = empty; 1..8 = (option index + 1). A ballot is a
///            PREFIX of distinct, in-range options (rank your top-k; the rest
///            are empty).
///
///         2. The WINNER is computed OFF-CHAIN. This contract is STORAGE + a
///            ROUND-1 FIRST-PREFERENCE tally ONLY — it does NOT run IRV. The
///            full ranking of every ballot is emitted in VoteCast(packedRanking)
///            so any verifier can read every ballot and replay the canonical IRV
///            rule (see docs/superpowers/specs/2026-06-02-ranked-choice-design.md)
///            to a deterministic winner.
///
///         IMPORTANT: getResults() returns round-1 first-preference counts ONLY.
///         The first-preference leader is FREQUENTLY NOT the IRV winner — nothing
///         may treat max(getResults()) as the outcome.
///
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy
///         compatibility.
contract ZkRankedVoting is IZkPoll, Initializable, Ownable {
    /// @notice Max number of options. Each ballot packs up to MAX_OPTIONS rank
    ///         slots of 4 bits each into the Semaphore `message` field, so the
    ///         packed value uses 8 × 4 = 32 bits and stays exact under the web
    ///         prover's `Number(message)` (IEEE-754 double, 53-bit precision).
    ///         Ranked-choice with >8 options is rare and encoding-heavy, so 8 is
    ///         the conservative cap.
    uint256 public constant MAX_OPTIONS = 8;

    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;

    string[] public options;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    uint256 public participantCount;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 packedRanking);
    event PollClosed();
    event OptionAdded(string label);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initialize the clone (replaces constructor)
    /// @param _semaphoreAddress  Address of the Semaphore contract
    /// @param _owner             Poll owner / admin
    /// @param _initialOptions    Initial set of voting options
    function initialize(
        address _semaphoreAddress,
        address _owner,
        string[] calldata _initialOptions
    ) external initializer {
        if (_initialOptions.length > MAX_OPTIONS) revert TooManyOptions();

        semaphore = ISemaphore(_semaphoreAddress);
        _transferOwnership(_owner);
        state = PollState.Registration;

        groupId = semaphore.createGroup(address(this));

        for (uint256 i = 0; i < _initialOptions.length; i++) {
            options.push(_initialOptions[i]);
            emit OptionAdded(_initialOptions[i]);
        }
    }

    // ── IZkPoll views ───────────────────────────────────────────────

    /// @dev Resolves diamond inheritance between IZkPoll.owner() and Ownable.owner().
    function owner() public view override(IZkPoll, Ownable) returns (address) {
        return Ownable.owner();
    }

    function getState() external view override returns (PollState) {
        return state;
    }

    /// @notice ROUND-1 FIRST-PREFERENCE counts ONLY — NOT the IRV winner.
    /// @dev The first-preference leader is frequently NOT the instant-runoff
    ///      winner. The winner is computed off-chain by replaying the canonical
    ///      IRV rule over the full ballots emitted in VoteCast. Nothing may treat
    ///      max(getResults()) as the outcome.
    function getResults() external view override returns (uint256[] memory) {
        uint256[] memory results = new uint256[](options.length);
        for (uint256 i = 0; i < options.length; i++) {
            results[i] = voteCounts[i];
        }
        return results;
    }

    function getOptions() external view override returns (string[] memory) {
        return options;
    }

    function getParticipantCount() external view override returns (uint256) {
        return participantCount;
    }

    function verifyParticipation(uint256 nullifierHash) external view override returns (bool) {
        return isNullifierUsed[nullifierHash];
    }

    // ── Admin: Manage Options (Registration phase only) ─────────────

    function addOption(string calldata label) external onlyOwner {
        if (state != PollState.Registration) revert NotInRegistration();
        if (options.length >= MAX_OPTIONS) revert TooManyOptions();
        options.push(label);
        emit OptionAdded(label);
    }

    function getOptionCount() external view returns (uint256) {
        return options.length;
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

    function startVoting() external onlyOwner {
        if (state != PollState.Registration) revert CanOnlyStartFromRegistration();
        if (options.length < 2) revert NeedAtLeastTwoOptions();
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
    // A valid ballot is a PREFIX of distinct, in-range options encoded as 4-bit
    // rank slots in `packedRanking`: slot i = (packedRanking >> (4*i)) & 0xF,
    // value 0 = empty, 1..8 = (option index + 1).
    //
    // Reverts EmptyBallot if zero options are ranked (slot 0 empty), else
    // InvalidBallot for: bits above bit 32, a gap (nonzero slot after an empty
    // one), an out-of-range option (slot > options.length), or a duplicate
    // option. ≤8 iterations ⇒ gas is trivial.
    function _validateRanking(uint256 packedRanking) internal view {
        // High-bits guard is SEPARATE: the slot loop below only inspects bits
        // 0..31, so a valid low-32 prefix plus garbage above bit 32 would sail
        // through it. Reject anything with bits at/above bit (4 * MAX_OPTIONS).
        if (packedRanking >= (1 << (4 * MAX_OPTIONS))) revert InvalidBallot();
        // Slot 0 must rank a candidate — otherwise the ballot is empty.
        if ((packedRanking & 0xF) == 0) revert EmptyBallot();

        uint256 seen; // bitset of used option indices (bit (slot-1))
        bool ended; // have we hit the first empty slot?
        for (uint256 i = 0; i < MAX_OPTIONS; i++) {
            uint256 slot = (packedRanking >> (4 * i)) & 0xF;
            if (slot == 0) {
                ended = true; // empty slot ⇒ all higher slots must be empty
                continue;
            }
            if (ended) revert InvalidBallot(); // gap: nonzero slot after an empty one
            if (slot > options.length) revert InvalidBallot(); // out of range
            uint256 bit = 1 << (slot - 1);
            if (seen & bit != 0) revert InvalidBallot(); // duplicate option
            seen |= bit;
        }
    }

    // ── Voter: Cast an anonymous RANKED ballot using Semaphore ──────
    //
    // The `packedRanking` encodes a prefix of distinct options in preference
    // order (slot 0 = first choice). Every reject-check below runs BEFORE
    // isNullifierUsed is set, so a rejected ballot never consumes the nullifier —
    // the voter can retry with a valid ballot using the same identity (same
    // nullifier). The on-chain tally increments the FIRST PREFERENCE ONLY; the
    // full ranking is emitted in VoteCast so the off-chain IRV can read every
    // ballot. getResults() is therefore round-1 first-prefs, NOT the winner.
    function castVote(uint256 packedRanking, ISemaphore.SemaphoreProof calldata proof) external {
        if (state != PollState.Voting) revert NotInVoting();

        // Validate the packed ranking (EmptyBallot if zero ranked, InvalidBallot
        // if malformed). All ballot reverts fire BEFORE the nullifier write.
        _validateRanking(packedRanking);

        if (isNullifierUsed[proof.nullifier]) revert AlreadyVoted();

        if (proof.scope != uint256(uint160(address(this)))) revert InvalidScope();
        if (proof.message != packedRanking) revert TamperedVoteSignal(); // bind ballot to proof

        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidProof();

        isNullifierUsed[proof.nullifier] = true;

        // FIRST-PREFERENCE tally only. (packedRanking & 0xF) is guaranteed ≥ 1 by
        // _validateRanking, so the `- 1` cannot underflow. Lower ranks are NOT
        // counted on-chain — the IRV winner is computed off-chain from VoteCast.
        uint256 firstChoice = (packedRanking & 0xF) - 1;
        voteCounts[firstChoice]++;

        emit VoteCast(packedRanking);
    }
}
