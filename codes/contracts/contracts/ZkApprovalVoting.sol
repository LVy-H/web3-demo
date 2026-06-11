// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkApprovalVoting}.
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
error InvalidResultsPolicy(uint8 resultsPolicy);

/// @title ZkApprovalVoting (M3)
/// @notice Approval voting module implementing IZkPoll. A sibling of M1
///         ZkAnonVoting: identical Semaphore membership / registration /
///         nullifier model and relayer-submitted anonymity. The difference is
///         the ballot — a voter approves ANY NUMBER of options, encoded as a
///         BITMASK in the Semaphore `message` field (bit i set ⇒ option i is
///         approved). The tally increments EVERY approved option, so per-option
///         counts are approvals (their sum can exceed the voter count), not
///         exclusive votes.
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy
///         compatibility.
contract ZkApprovalVoting is IZkPoll, Initializable, Ownable {
    /// @notice Max number of options. The off-chain prover bridge
    ///         (codes/mobile/web_prover/entry.js) does `Number(message)`; a JS
    ///         Number holds 53 bits of integer precision, so a bitmask
    ///         round-trips exactly well past 32 bits. 32 is a conservative
    ///         sanity / UI guardrail (one 32-bit word, manageable checkbox UI),
    ///         not a correctness boundary — the on-chain bitmask is a full uint256.
    uint256 public constant MAX_OPTIONS = 32;

    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;

    string[] public options;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    uint256 public participantCount;

    /// @notice Results-timing policy (R4): 0 = sealed-until-close (DEFAULT),
    ///         1 = live-public (creation-time opt-in). See {IZkPoll-resultsPolicy}
    ///         for the v1 enforcement note: metadata honored by compliant
    ///         clients/relayer, NOT an on-chain seal — getResults() stays open
    ///         because ballots are public calldata anyway.
    uint8 public override resultsPolicy;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 bitmask);
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
    /// @param _resultsPolicy     0 = sealed-until-close (default), 1 = live-public
    function initialize(
        address _semaphoreAddress,
        address _owner,
        string[] calldata _initialOptions,
        uint8 _resultsPolicy
    ) external initializer {
        if (_initialOptions.length > MAX_OPTIONS) revert TooManyOptions();
        if (_resultsPolicy > 1) revert InvalidResultsPolicy(_resultsPolicy);
        resultsPolicy = _resultsPolicy;

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

    // ── Voter: Cast an anonymous APPROVAL ballot using Semaphore ────
    //
    // The `bitmask` encodes the approved set: bit i set ⇒ option i approved.
    // Every reject-check below runs BEFORE isNullifierUsed is set, so a rejected
    // ballot never consumes the nullifier — the voter can retry with a valid
    // ballot using the same identity (same nullifier). The tally increments
    // EVERY approved option, so per-option counts are approvals, not exclusive
    // votes (their sum can exceed the voter count).
    function castVote(uint256 bitmask, ISemaphore.SemaphoreProof calldata proof) external {
        if (state != PollState.Voting) revert NotInVoting();
        if (bitmask == 0) revert EmptyBallot(); // no empty ballot
        // No out-of-range bits. Range is [1, 2^options.length). options.length
        // is capped at MAX_OPTIONS (32) so (1 << options.length) never overflows
        // a uint256.
        if (bitmask >= (1 << options.length)) revert InvalidBallot();
        if (isNullifierUsed[proof.nullifier]) revert AlreadyVoted();

        if (proof.scope != uint256(uint160(address(this)))) revert InvalidScope();
        if (proof.message != bitmask) revert TamperedVoteSignal(); // bind ballot to proof

        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidProof();

        isNullifierUsed[proof.nullifier] = true;
        for (uint256 i = 0; i < options.length; i++) {
            if ((bitmask >> i) & 1 == 1) voteCounts[i]++;
        }

        emit VoteCast(bitmask);
    }
}
