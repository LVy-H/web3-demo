// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@semaphore-protocol/contracts/interfaces/ISemaphoreVerifier.sol";

/// @title MockSemaphoreVerifier
/// @notice A test-only verifier that always returns true.
///         DO NOT deploy to mainnet or any public network.
/// @dev Used in local Hardhat tests so that SNARK artifacts do not need to be downloaded.
contract MockSemaphoreVerifier is ISemaphoreVerifier {
    function verifyProof(
        uint[2] calldata,
        uint[2][2] calldata,
        uint[2] calldata,
        uint[4] calldata,
        uint
    ) external pure override returns (bool) {
        return true;
    }
}
