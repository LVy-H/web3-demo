// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/Semaphore.sol";
import "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol";

contract ZkVotingLottery {
    ISemaphore public semaphore;
    uint256 public groupId;

    enum PollState {
        Registration,
        Voting,
        Ended
    }
    PollState public state;

    address public owner;

    // Tracking used nullifiers to prevent double voting and for the lottery
    mapping(uint256 => bool) public isNullifierUsed;
    uint256[] public usedNullifiersList;

    // Store votes for candidates
    mapping(uint256 => uint256) public voteCounts;

    // Lottery tracking
    uint256 public winningNullifier;
    bool public prizeClaimed;

    event VoterRegistered(uint256 identityCommitment);
    event VoteCast(uint256 candidate);
    event PollClosed();
    event LotteryDrawn(uint256 winningNullifier);
    event PrizeClaimed(address indexed receiver, uint256 winningNullifier);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _semaphoreAddress) {
        semaphore = ISemaphore(_semaphoreAddress);
        owner = msg.sender;
        state = PollState.Registration;

        // V4 creates the groupId automatically and returns it
        groupId = semaphore.createGroup(address(this));
    }

    function registerVoter(uint256 identityCommitment) external {
        require(state == PollState.Registration, "Not in registration phase");

        semaphore.addMember(groupId, identityCommitment);

        emit VoterRegistered(identityCommitment);
    }

    function startVoting() external onlyOwner {
        require(
            state == PollState.Registration,
            "Can only start from registration"
        );
        state = PollState.Voting;
    }

    function endVotingAndDrawLottery() external onlyOwner {
        require(state == PollState.Voting, "Not in voting phase");
        state = PollState.Ended;

        emit PollClosed();

        if (usedNullifiersList.length > 0) {
            // Pseudo-random generation for PoC. DO NOT USE IN PRODUCTION.
            // In production, use Chainlink VRF.
            uint256 randomWord = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        blockhash(block.number - 1)
                    )
                )
            );
            uint256 winningIndex = randomWord % usedNullifiersList.length;
            winningNullifier = usedNullifiersList[winningIndex];

            emit LotteryDrawn(winningNullifier);
        }
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
        usedNullifiersList.push(proof.nullifier);
        voteCounts[vote]++;

        emit VoteCast(vote);
    }

    // Winner proves ownership of the winning nullifier to claim funds
    function claimPrize(
        address receiver,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == PollState.Ended, "Lottery not concluded");
        require(!prizeClaimed, "Prize already claimed");
        require(winningNullifier != 0, "No winner drawn");

        // Ensure the proof is specifically for claiming the prize
        uint256 claimScope = uint256(keccak256("CLAIM_PRIZE_SCOPE"));
        require(proof.scope == claimScope, "Invalid claim scope");
        require(
            proof.message == uint256(uint160(receiver)),
            "Receiver mismatch"
        );

        bool isValid = semaphore.verifyProof(groupId, proof);
        require(isValid, "Invalid claim proof");

        prizeClaimed = true;

        emit PrizeClaimed(receiver, proof.nullifier);
    }

    // Allow deposit of prize funds
    receive() external payable {}
}
