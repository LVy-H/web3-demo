// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkQuadraticVoting}.
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
error OverBudget();
error AlreadyVoted();
error InvalidScope();
error TamperedVoteSignal();
error InvalidProof();

/// @title ZkQuadraticVoting (Phase 12c)
/// @notice Quadratic-voting (QV) module implementing IZkPoll. A structural
///         sibling of M3 ZkApprovalVoting: identical Semaphore membership /
///         registration / nullifier model and the same relayer-submitted
///         anonymity. The difference is the ballot — a voter spends a FIXED,
///         UNIFORM budget of CREDITS across the options, where casting vᵢ votes
///         for option i costs vᵢ². The allocation vector is encoded as 4-bit
///         slots in the Semaphore `message` field: vᵢ = (packedAlloc >> (4*i)) & 0xF.
///
///         UNIFORM budget (every voter gets the SAME CREDITS): true per-voter
///         budgets cannot be proven anonymously with the stock Semaphore circuit
///         (it proves "some member" + a nullifier, not a per-member credit
///         balance). Equal credits is the maximal QV variant that keeps the
///         M1/M2/M3 anonymity model intact. See
///         docs/superpowers/specs/2026-06-03-quadratic-voting-design.md.
///
///         getResults() IS the authoritative tally: a per-option, on-chain SUM
///         OF THE VOTES vᵢ allocated to each option across all ballots. Unlike
///         M2 ranked-choice there is NO off-chain replay — the option with the
///         highest getResults() entry is the winner. The QV nonlinearity lives
///         entirely in the cost function (vᵢ² against CREDITS) enforced at cast
///         time; accepted votes are then summed linearly on-chain.
///
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy
///         compatibility.
contract ZkQuadraticVoting is IZkPoll, Initializable, Ownable {
    /// @notice Max number of options. Each ballot packs up to MAX_OPTIONS
    ///         allocation slots of 4 bits each into the Semaphore `message`
    ///         field, so the packed value uses 8 × 4 = 32 bits and stays exact
    ///         under the web prover's `Number(message)` (IEEE-754 double, 53-bit
    ///         precision). QV with >8 options is rare and encoding-heavy, so 8 is
    ///         the conservative cap (matches M2). Enforced at initialize().
    uint256 public constant MAX_OPTIONS = 8;

    /// @notice The uniform vote-credit budget every voter receives. Casting vᵢ
    ///         votes for option i costs vᵢ²; a ballot is valid iff Σ vᵢ² ≤ CREDITS.
    ///         100 caps a single option at v=10 (10²=100), well under the 4-bit
    ///         field max of 15, so the encoding never clips a legal ballot.
    uint256 public constant CREDITS = 100;

    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;

    string[] public options;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    uint256 public participantCount;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 packedAlloc);
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

    /// @notice AUTHORITATIVE per-option tally — the on-chain SUM of votes vᵢ
    ///         allocated to each option across all accepted ballots. This IS the
    ///         outcome: the option with the highest entry wins. There is NO
    ///         off-chain replay (contrast M2 ranked-choice).
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
    // A valid ballot is an allocation vector encoded as 4-bit slots in
    // `packedAlloc`: vᵢ = (packedAlloc >> (4*i)) & 0xF is the number of votes for
    // option i. It is valid iff:
    //
    //   - every slot at index i ≥ options.length is 0 (ghost-slot rule) — no
    //     allocation to a non-existent option, else InvalidBallot,
    //   - Σ vᵢ² (over i < options.length) ≤ CREDITS (within budget), else OverBudget,
    //   - Σ vᵢ  (over i < options.length) ≥ 1 (not empty), else EmptyBallot,
    //   - packedAlloc < (1 << (4 * MAX_OPTIONS)) (no bits above bit 32), else
    //     InvalidBallot.
    //
    // ≤8 iterations ⇒ gas is trivial. This is `view` and reverts on the first
    // failing rule; the order (ghost-slot → budget → empty → high-bits) matters:
    // a bare ghost ballot (real options all 0, a nonzero ghost slot) has
    // sumV(real) = 0, and MUST surface as InvalidBallot (a malformed ballot), not
    // EmptyBallot — so the ghost-slot check runs first.
    function _validateAllocation(uint256 packedAlloc) internal view {
        uint256 len = options.length;

        // 1. Ghost-slot rule: every slot at index ≥ options.length must be 0.
        //    Bounded by MAX_OPTIONS; when len == MAX_OPTIONS this loop runs zero
        //    iterations (and the high-bits guard below is what catches bits ≥32).
        for (uint256 i = len; i < MAX_OPTIONS; i++) {
            if ((packedAlloc >> (4 * i)) & 0xF != 0) revert InvalidBallot();
        }

        // 2. Budget: Σ vᵢ² ≤ CREDITS, summed over real options only.
        // 3. Non-empty: Σ vᵢ ≥ 1, summed over real options only.
        uint256 sumSq;
        uint256 sumV;
        for (uint256 i = 0; i < len; i++) {
            uint256 v = (packedAlloc >> (4 * i)) & 0xF; // 0..15
            sumSq += v * v;
            sumV += v;
        }
        if (sumSq > CREDITS) revert OverBudget();
        if (sumV < 1) revert EmptyBallot();

        // 4. High-bits guard (SEPARATE from the ghost-slot loop, which is a no-op
        //    when len == MAX_OPTIONS): reject anything with bits at/above bit
        //    (4 * MAX_OPTIONS).
        if (packedAlloc >= (1 << (4 * MAX_OPTIONS))) revert InvalidBallot();
    }

    // ── Voter: Cast an anonymous QUADRATIC ballot using Semaphore ────
    //
    // The `packedAlloc` encodes an allocation of the uniform CREDITS budget over
    // the options (vᵢ votes for option i, cost vᵢ²). Every reject-check below
    // runs BEFORE isNullifierUsed is set, so a rejected ballot never consumes the
    // nullifier — the voter can retry with a valid ballot using the same identity
    // (same nullifier). The on-chain tally adds the VOTES vᵢ (not the cost) to
    // each option; getResults() is therefore the authoritative per-option vote
    // sum (no off-chain replay).
    function castVote(uint256 packedAlloc, ISemaphore.SemaphoreProof calldata proof) external {
        if (state != PollState.Voting) revert NotInVoting();

        // Validate the packed allocation (ghost-slot → OverBudget → EmptyBallot →
        // high-bits). All ballot reverts fire BEFORE the nullifier write.
        _validateAllocation(packedAlloc);

        if (isNullifierUsed[proof.nullifier]) revert AlreadyVoted();

        if (proof.scope != uint256(uint160(address(this)))) revert InvalidScope();
        if (proof.message != packedAlloc) revert TamperedVoteSignal(); // bind ballot to proof

        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidProof();

        isNullifierUsed[proof.nullifier] = true;

        // Tally the VOTES vᵢ (not the cost vᵢ²) per option. Bounded by
        // options.length; the ghost-slot rule guarantees every slot ≥ len is 0,
        // so nothing outside this range was allocated.
        for (uint256 i = 0; i < options.length; i++) {
            voteCounts[i] += (packedAlloc >> (4 * i)) & 0xF;
        }

        emit VoteCast(packedAlloc);
    }
}
