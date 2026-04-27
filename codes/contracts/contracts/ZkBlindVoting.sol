// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IZkPoll.sol";

/// @notice Errors for {ZkBlindVoting}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount, InvalidInitialization, etc.)
///      cover access-control / lifecycle reverts; these are the module's local errors.
error NotInRegistration();
error NotInVoting();
error NotInEnded();
error CanOnlyStartFromRegistration();
error NeedAtLeastTwoOptions();
error NeedAtLeastOneVoter();
error AlreadyRegistered();
error NotRegistered();
error AlreadyCommitted();
error EmptyCommitHash();
error NoCommitFound();
error AlreadyRevealed();
error InvalidOptionIndex();
error HashMismatch();
error RevealDeadlinePassed();
error RevealDeadlineNotPassed();
error AlreadyFinalized();

/// @title ZkBlindVoting (M2)
/// @notice Commit-reveal blind voting module implementing IZkPoll.
///         Voter identity (address) is public, but vote content is hidden
///         during the voting phase via hash commitments.
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy compatibility.
///
///         Flow: Registration → Voting (commit) → Ended (reveal window → finalize)
contract ZkBlindVoting is IZkPoll, Initializable, Ownable {
    struct VoteCommit {
        bytes32 commitHash; // keccak256(abi.encodePacked(optionIndex, salt))
        bool revealed;
        uint256 revealedOption;
    }

    PollState public state;

    string[] public options;

    mapping(address => VoteCommit) public commits;
    mapping(address => bool) public isRegistered;
    address[] public voters;
    uint256 public participantCount;

    uint256 public revealDuration; // seconds after voting ends before reveal window closes
    uint256 public revealDeadline; // timestamp after which reveals are closed
    bool public resultsFinalized;

    mapping(uint256 => uint256) public voteCounts; // populated as reveals happen

    event VoterRegistered(address indexed voter);
    event VoteCommitted(address indexed voter);
    event VoteRevealed(address indexed voter, uint256 optionIndex);
    event ResultsFinalized();
    event OptionAdded(string label);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initialize the clone (replaces constructor)
    /// @param _owner           Poll owner / admin
    /// @param _initialOptions  Initial set of voting options
    /// @param _revealDuration  Seconds after voting ends before reveal window closes
    function initialize(
        address _owner,
        string[] calldata _initialOptions,
        uint256 _revealDuration
    ) external initializer {
        _transferOwnership(_owner);
        state = PollState.Registration;
        revealDuration = _revealDuration;

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

    /// @notice For IZkPoll compatibility. Interprets nullifierHash as address(uint160(nullifierHash)).
    ///         Returns true if that address has committed a vote.
    function verifyParticipation(
        uint256 nullifierHash
    ) external view override returns (bool) {
        address voter = address(uint160(nullifierHash));
        return commits[voter].commitHash != bytes32(0);
    }

    // ── Public: voter status queries ────────────────────────────────

    function hasVoted(address voter) external view returns (bool) {
        return commits[voter].commitHash != bytes32(0);
    }

    function hasRevealed(address voter) external view returns (bool) {
        return commits[voter].revealed;
    }

    function getRevealDeadline() external view returns (uint256) {
        return revealDeadline;
    }

    function isFinalized() external view returns (bool) {
        return resultsFinalized;
    }

    function getOptionCount() external view returns (uint256) {
        return options.length;
    }

    function getVoters() external view returns (address[] memory) {
        return voters;
    }

    // ── Admin: Manage Options (Registration phase only) ─────────────

    function addOption(string calldata label) external onlyOwner {
        if (state != PollState.Registration) revert NotInRegistration();
        options.push(label);
        emit OptionAdded(label);
    }

    // ── Voter: Registration ─────────────────────────────────────────

    /// @notice Register msg.sender as a voter. Only during Registration.
    function register() external {
        if (state != PollState.Registration) revert NotInRegistration();
        if (isRegistered[msg.sender]) revert AlreadyRegistered();

        isRegistered[msg.sender] = true;
        voters.push(msg.sender);
        participantCount++;

        emit VoterRegistered(msg.sender);
    }

    // ── Admin: Poll Lifecycle ───────────────────────────────────────

    /// @notice Transition Registration → Voting. Requires >= 2 options and >= 1 voter.
    function startVoting() external onlyOwner {
        if (state != PollState.Registration) revert CanOnlyStartFromRegistration();
        if (options.length < 2) revert NeedAtLeastTwoOptions();
        if (participantCount < 1) revert NeedAtLeastOneVoter();

        state = PollState.Voting;
        emit StateChanged(PollState.Voting);
    }

    /// @notice Transition Voting → Ended. Sets revealDeadline.
    function endVoting() external onlyOwner {
        if (state != PollState.Voting) revert NotInVoting();

        state = PollState.Ended;
        revealDeadline = block.timestamp + revealDuration;

        emit StateChanged(PollState.Ended);
    }

    // ── Voter: Commit a vote ────────────────────────────────────────

    /// @notice Commit a vote hash. During Voting only. Voter must be registered.
    /// @param commitHash  keccak256(abi.encodePacked(optionIndex, salt))
    function commitVote(bytes32 commitHash) external {
        if (state != PollState.Voting) revert NotInVoting();
        if (!isRegistered[msg.sender]) revert NotRegistered();
        if (commits[msg.sender].commitHash != bytes32(0)) revert AlreadyCommitted();
        if (commitHash == bytes32(0)) revert EmptyCommitHash();

        commits[msg.sender] = VoteCommit({
            commitHash: commitHash,
            revealed: false,
            revealedOption: 0
        });

        emit VoteCommitted(msg.sender);
    }

    // ── Voter: Reveal a vote ────────────────────────────────────────

    /// @notice Reveal a previously committed vote.
    ///         Must be in Ended state, before revealDeadline, and not yet finalized.
    /// @param optionIndex  The option index that was committed
    /// @param salt         The salt used in the commitment
    function revealVote(uint256 optionIndex, bytes32 salt) external {
        if (state != PollState.Ended) revert NotInEnded();
        if (block.timestamp > revealDeadline) revert RevealDeadlinePassed();
        if (resultsFinalized) revert AlreadyFinalized();
        if (commits[msg.sender].commitHash == bytes32(0)) revert NoCommitFound();
        if (commits[msg.sender].revealed) revert AlreadyRevealed();
        if (optionIndex >= options.length) revert InvalidOptionIndex();

        bytes32 expectedHash = keccak256(
            abi.encodePacked(optionIndex, salt)
        );
        if (expectedHash != commits[msg.sender].commitHash) revert HashMismatch();

        commits[msg.sender].revealed = true;
        commits[msg.sender].revealedOption = optionIndex;
        voteCounts[optionIndex]++;

        emit VoteRevealed(msg.sender, optionIndex);
    }

    // ── Admin: Finalize results ─────────────────────────────────────

    /// @notice Finalize results after reveal deadline. Unrevealed votes are excluded.
    function finalizeResults() external onlyOwner {
        if (state != PollState.Ended) revert NotInEnded();
        if (block.timestamp <= revealDeadline) revert RevealDeadlineNotPassed();
        if (resultsFinalized) revert AlreadyFinalized();

        resultsFinalized = true;
        emit ResultsFinalized();
    }
}
