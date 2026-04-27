// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import "@semaphore-protocol/contracts/Semaphore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
error ClaimingNotEnded();
error ZeroRecipient();
error NothingToWithdraw();
error WithdrawFailed();

contract ZkAirdrop is Ownable, ReentrancyGuard {
    ISemaphore public semaphore;
    uint256 public groupId;

    enum AirdropState {
        Registration,
        Claiming,
        Ended
    }
    AirdropState public state;

    // Tracking used nullifiers to ensure each user claims only once
    mapping(uint256 => bool) public isNullifierUsed;

    uint256 public airdropAmount;

    event MemberRegistered(uint256 identityCommitment);
    event AirdropClaimed(address indexed receiver, uint256 nullifier);
    event AirdropStarted();
    event ClaimingEnded();
    event UnclaimedWithdrawn(address indexed to, uint256 amount);

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
    ) external nonReentrant {
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

    /// @notice Owner closes the claiming phase. After this no further claims
    ///         are accepted and unclaimed ETH can be recovered via
    ///         {withdrawUnclaimed}.
    function endClaiming() external onlyOwner {
        if (state != AirdropState.Claiming) revert NotInClaiming();
        state = AirdropState.Ended;
        emit ClaimingEnded();
    }

    /// @notice Owner-only escape hatch: drain remaining ETH after claiming
    ///         has ended. Can only be called once the state is Ended (set
    ///         via {endClaiming}).
    function withdrawUnclaimed(address to) external onlyOwner {
        if (state != AirdropState.Ended) revert ClaimingNotEnded();
        if (to == address(0)) revert ZeroRecipient();
        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToWithdraw();
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert WithdrawFailed();
        emit UnclaimedWithdrawn(to, balance);
    }

    // Allow owner or anyone to deposit ETH to fund the airdrop pool
    receive() external payable {}
}
