// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkAnonVoting}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount, InvalidInitialization, etc.)
///      cover access-control / lifecycle reverts; these are the module's local errors.
error NotInRegistration();
error NotInVoting();
error CanOnlyStartFromRegistration();
error NeedAtLeastTwoOptions();
error NeedAtLeastOneVoter();
error EmptyBatch();
error BatchTooLarge();
error AlreadyRegistered();
error DuplicateInBatch();
error InvalidOptionIndex();
error AlreadyVoted();
error InvalidScope();
error TamperedVoteSignal();
error InvalidProof();

/// @title ZkAnonVoting (M1)
/// @notice Anonymous voting module implementing IZkPoll.
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy compatibility.
contract ZkAnonVoting is IZkPoll, Initializable, Ownable {
    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;

    string[] public options;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    uint256 public participantCount;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 optionIndex);
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
        // Cap chosen so a full batch fits a mainnet block. Semaphore.addMember
        // cost grows with tree depth; ~50 inserts ≈ 24.5M gas (< 30M block
        // limit), whereas 100 ≈ 50M gas is unreachable on-chain. Chunk larger
        // registrations client-side. (See improvements/findings.md P1-13.)
        if (identityCommitments.length > 50) revert BatchTooLarge();

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

    // ── Voter: Cast an anonymous vote using Semaphore ───────────────

    function castVote(uint256 vote, ISemaphore.SemaphoreProof calldata proof) external {
        if (state != PollState.Voting) revert NotInVoting();
        if (vote >= options.length) revert InvalidOptionIndex();
        if (isNullifierUsed[proof.nullifier]) revert AlreadyVoted();

        if (proof.scope != uint256(uint160(address(this)))) revert InvalidScope();
        if (proof.message != vote) revert TamperedVoteSignal();

        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidProof();

        isNullifierUsed[proof.nullifier] = true;
        voteCounts[vote]++;

        emit VoteCast(vote);
    }
}
