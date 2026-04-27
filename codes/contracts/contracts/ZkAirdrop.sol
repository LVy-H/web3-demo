// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/Semaphore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Errors for {ZkAirdrop}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount) cover access-control reverts;
///      these are the contract's local errors.
error NotInRegistration();
error NotInClaiming();
error CanOnlyStartFromRegistration();
error AirdropAlreadyClaimed();
error InvalidClaimScope();
error ReceiverMismatch();
error InvalidClaimProof();
error EthTransferFailed();

contract ZkAirdrop is Ownable {
    ISemaphore public semaphore;
    uint256 public groupId;

    enum AirdropState {
        Registration,
        Claiming
    }
    AirdropState public state;

    // Tracking used nullifiers to ensure each user claims only once
    mapping(uint256 => bool) public isNullifierUsed;

    uint256 public airdropAmount;

    event MemberRegistered(uint256 identityCommitment);
    event AirdropClaimed(address indexed receiver, uint256 nullifier);
    event AirdropStarted();

    constructor(
        address _semaphoreAddress,
        uint256 _airdropAmount
    ) Ownable(msg.sender) {
        semaphore = ISemaphore(_semaphoreAddress);
        airdropAmount = _airdropAmount;
        state = AirdropState.Registration;

        groupId = semaphore.createGroup(address(this));
    }

    function registerMember(uint256 identityCommitment) external {
        if (state != AirdropState.Registration) revert NotInRegistration();

        semaphore.addMember(groupId, identityCommitment);

        emit MemberRegistered(identityCommitment);
    }

    function startAirdrop() external onlyOwner {
        if (state != AirdropState.Registration) revert CanOnlyStartFromRegistration();
        state = AirdropState.Claiming;

        emit AirdropStarted();
    }

    // Winner proves membership in the group to claim exactly 1 predefined amount of funds
    function claimAirdrop(
        address receiver,
        ISemaphore.SemaphoreProof calldata proof
    ) external {
        if (state != AirdropState.Claiming) revert NotInClaiming();
        if (isNullifierUsed[proof.nullifier]) revert AirdropAlreadyClaimed();

        // Scope to this specific airdrop contract to prevent replay attacks
        if (proof.scope != uint256(uint160(address(this)))) revert InvalidClaimScope();
        if (proof.message != uint256(uint160(receiver))) revert ReceiverMismatch();

        bool isValid = semaphore.verifyProof(groupId, proof);
        if (!isValid) revert InvalidClaimProof();

        isNullifierUsed[proof.nullifier] = true;

        emit AirdropClaimed(receiver, proof.nullifier);

        // Try to send the ETH
        (bool success, ) = receiver.call{value: airdropAmount}("");
        if (!success) revert EthTransferFailed();
    }

    // Allow owner or anyone to deposit ETH to fund the airdrop pool
    receive() external payable {}
}
