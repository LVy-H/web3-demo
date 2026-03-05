// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/Semaphore.sol";

contract ZkAirdrop {
    ISemaphore public semaphore;
    uint256 public groupId;

    enum AirdropState {
        Registration,
        Claiming
    }
    AirdropState public state;

    address public owner;

    // Tracking used nullifiers to ensure each user claims only once
    mapping(uint256 => bool) public isNullifierUsed;

    uint256 public airdropAmount;

    event MemberRegistered(uint256 identityCommitment);
    event AirdropClaimed(address indexed receiver, uint256 nullifier);
    event AirdropStarted();

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _semaphoreAddress, uint256 _airdropAmount) {
        semaphore = ISemaphore(_semaphoreAddress);
        owner = msg.sender;
        airdropAmount = _airdropAmount;
        state = AirdropState.Registration;

        groupId = semaphore.createGroup(address(this));
    }

    function registerMember(uint256 identityCommitment) external {
        require(
            state == AirdropState.Registration,
            "Not in registration phase"
        );

        semaphore.addMember(groupId, identityCommitment);

        emit MemberRegistered(identityCommitment);
    }

    function startAirdrop() external onlyOwner {
        require(
            state == AirdropState.Registration,
            "Can only start from registration"
        );
        state = AirdropState.Claiming;

        emit AirdropStarted();
    }

    // Winner proves membership in the group to claim exactly 1 predefined amount of funds
    function claimAirdrop(
        address receiver,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        require(state == AirdropState.Claiming, "Not in claiming phase");
        require(
            !isNullifierUsed[proof.nullifier],
            "Airdrop already claimed by this identity"
        );

        // Scope to this specific airdrop contract to prevent replay attacks
        require(
            proof.scope == uint256(uint160(address(this))),
            "Invalid claim scope"
        );
        require(
            proof.message == uint256(uint160(receiver)),
            "Receiver mismatch"
        );

        bool isValid = semaphore.verifyProof(groupId, proof);
        require(isValid, "Invalid claim proof");

        isNullifierUsed[proof.nullifier] = true;

        emit AirdropClaimed(receiver, proof.nullifier);

        // Try to send the ETH
        (bool success, ) = receiver.call{value: airdropAmount}("");
        require(success, "Failed to send ETH");
    }

    // Allow owner or anyone to deposit ETH to fund the airdrop pool
    receive() external payable {}
}
