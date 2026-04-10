// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "./interfaces/IZkPoll.sol";

/// @title ZkAnonVoting (M1)
/// @notice Anonymous voting module implementing IZkPoll.
///         Uses initialize() instead of constructor for EIP-1167 minimal proxy compatibility.
contract ZkAnonVoting is IZkPoll {
    ISemaphore public semaphore;
    uint256 public groupId;

    PollState public state;
    address public override owner;

    bool private _initialized;

    string[] public options;

    mapping(uint256 => bool) public isNullifierUsed;
    mapping(uint256 => bool) public registeredCommitments;
    mapping(uint256 => uint256) public voteCounts;

    uint256 public participantCount;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 optionIndex);
    event PollClosed();
    event OptionAdded(string label);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Initialize the clone (replaces constructor)
    /// @param _semaphoreAddress  Address of the Semaphore contract
    /// @param _owner             Poll owner / admin
    /// @param _initialOptions    Initial set of voting options
    function initialize(
        address _semaphoreAddress,
        address _owner,
        string[] calldata _initialOptions
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        semaphore = ISemaphore(_semaphoreAddress);
        owner = _owner;
        state = PollState.Registration;

        groupId = semaphore.createGroup(address(this));

        for (uint256 i = 0; i < _initialOptions.length; i++) {
            options.push(_initialOptions[i]);
            emit OptionAdded(_initialOptions[i]);
        }
    }

    // ── IZkPoll views ───────────────────────────────────────────────

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

    function verifyParticipation(
        uint256 nullifierHash
    ) external view override returns (bool) {
        return isNullifierUsed[nullifierHash];
    }

    // ── Admin: Manage Options (Registration phase only) ─────────────

    function addOption(string calldata label) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        options.push(label);
        emit OptionAdded(label);
    }

    function getOptionCount() external view returns (uint256) {
        return options.length;
    }

    // ── Admin: Register Voters ──────────────────────────────────────

    function registerVoter(uint256 identityCommitment) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        require(
            !registeredCommitments[identityCommitment],
            "This identity is already registered"
        );

        registeredCommitments[identityCommitment] = true;
        participantCount++;
        semaphore.addMember(groupId, identityCommitment);

        emit VoterRegistered(identityCommitment);
    }

    function registerVoters(
        uint256[] calldata identityCommitments
    ) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");

        for (uint256 i = 0; i < identityCommitments.length; i++) {
            require(
                !registeredCommitments[identityCommitments[i]],
                "Duplicate identity in batch"
            );
            registeredCommitments[identityCommitments[i]] = true;
            participantCount++;
            semaphore.addMember(groupId, identityCommitments[i]);
            emit VoterRegistered(identityCommitments[i]);
        }
    }

    // ── Admin: Poll Lifecycle ───────────────────────────────────────

    function startVoting() external onlyOwner {
        require(
            state == PollState.Registration,
            "Can only start from registration"
        );
        require(options.length >= 2, "Need at least 2 options");
        state = PollState.Voting;
        emit StateChanged(PollState.Voting);
    }

    function endVoting() external onlyOwner {
        require(state == PollState.Voting, "Not in voting phase");
        state = PollState.Ended;
        emit StateChanged(PollState.Ended);
        emit PollClosed();
    }

    // ── Voter: Cast an anonymous vote using Semaphore ───────────────

    function castVote(
        uint256 vote,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == PollState.Voting, "Not in voting phase");
        require(vote < options.length, "Invalid option index");
        require(!isNullifierUsed[proof.nullifier], "You have already voted");

        require(
            proof.scope == uint256(uint160(address(this))),
            "Invalid scope"
        );
        require(proof.message == vote, "Tampered vote signal");

        bool isValid = semaphore.verifyProof(groupId, proof);
        require(isValid, "Invalid ZK proof");

        isNullifierUsed[proof.nullifier] = true;
        voteCounts[vote]++;

        emit VoteCast(vote);
    }
}
