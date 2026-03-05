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

    // Tracking used nullifiers to prevent double voting
    mapping(uint256 => bool) public isNullifierUsed;

    // Store votes for candidates
    mapping(uint256 => uint256) public voteCounts;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 candidate);
    event PollClosed();

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _semaphoreAddress, address _owner) {
        semaphore = ISemaphore(_semaphoreAddress);
        owner = _owner;
        state = PollState.Registration;

        groupId = semaphore.createGroup(address(this));
    }

    function registerVoter(uint256 identityCommitment) external {
        require(state == PollState.Registration, "Not in registration phase");

        semaphore.addMember(groupId, identityCommitment);

        emit VoterRegistered(identityCommitment);
    }

    function registerVoters(uint256[] calldata identityCommitments) external {
        require(state == PollState.Registration, "Not in registration phase");

        for (uint256 i = 0; i < identityCommitments.length; i++) {
            semaphore.addMember(groupId, identityCommitments[i]);
            emit VoterRegistered(identityCommitments[i]);
        }
    }

    function startVoting() external onlyOwner {
        require(
            state == PollState.Registration,
            "Can only start from registration"
        );
        state = PollState.Voting;
    }

    function endVoting() external onlyOwner {
        require(state == PollState.Voting, "Not in voting phase");
        state = PollState.Ended;

        emit PollClosed();
    }

    // Cast an anonymous vote using Semaphore
    function castVote(
        uint256 vote, // The signal (candidate ID)
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == PollState.Voting, "Not in voting phase");
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
