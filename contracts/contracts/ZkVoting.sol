// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/Semaphore.sol";

contract ZkVoting {
    ISemaphore public semaphore;
    uint256 public groupId;

    enum PollState {
        Registration,
        Voting,
        Ended
    }
    PollState public state;

    address public owner;

    // Dynamic poll options
    string[] public options;

    // Tracking used nullifiers to prevent double voting
    mapping(uint256 => bool) public isNullifierUsed;

    // Tracking registered commitments to prevent duplicate registration
    mapping(uint256 => bool) public registeredCommitments;

    // Store votes for each option index
    mapping(uint256 => uint256) public voteCounts;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 optionIndex);
    event PollClosed();
    event OptionAdded(string label);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _semaphoreAddress,
        address _owner,
        string[] memory _initialOptions
    ) {
        semaphore = ISemaphore(_semaphoreAddress);
        owner = _owner;
        state = PollState.Registration;

        groupId = semaphore.createGroup(address(this));

        for (uint256 i = 0; i < _initialOptions.length; i++) {
            options.push(_initialOptions[i]);
            emit OptionAdded(_initialOptions[i]);
        }
    }

    // --- Admin: Manage Options (Registration phase only) ---

    function addOption(string calldata label) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        options.push(label);
        emit OptionAdded(label);
    }

    function getOptions() external view returns (string[] memory) {
        return options;
    }

    function getOptionCount() external view returns (uint256) {
        return options.length;
    }

    // --- Admin: Register Voters (owner-only) ---

    function registerVoter(uint256 identityCommitment) external onlyOwner {
        require(state == PollState.Registration, "Not in registration phase");
        require(
            !registeredCommitments[identityCommitment],
            "This identity is already registered"
        );

        registeredCommitments[identityCommitment] = true;
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
            semaphore.addMember(groupId, identityCommitments[i]);
            emit VoterRegistered(identityCommitments[i]);
        }
    }

    // --- Admin: Poll Lifecycle ---

    function startVoting() external onlyOwner {
        require(
            state == PollState.Registration,
            "Can only start from registration"
        );
        require(options.length >= 2, "Need at least 2 options");
        state = PollState.Voting;
    }

    function endVoting() external onlyOwner {
        require(state == PollState.Voting, "Not in voting phase");
        state = PollState.Ended;

        emit PollClosed();
    }

    // --- Voter: Cast an anonymous vote using Semaphore ---

    function castVote(
        uint256 vote, // The option index (0-based)
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == PollState.Voting, "Not in voting phase");
        require(vote < options.length, "Invalid option index");
        require(!isNullifierUsed[proof.nullifier], "You have already voted");

        // Scope must be this contract's address to prevent replay across polls
        require(
            proof.scope == uint256(uint160(address(this))),
            "Invalid scope"
        );
        require(proof.message == vote, "Tampered vote signal");

        // Validate the ZK proof
        bool isValid = semaphore.verifyProof(groupId, proof);
        require(isValid, "Invalid ZK proof");

        // Record vote
        isNullifierUsed[proof.nullifier] = true;
        voteCounts[vote]++;

        emit VoteCast(vote);
    }
}
