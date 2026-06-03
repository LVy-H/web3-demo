// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Pulls the real Groth16 `SemaphoreVerifier` from @semaphore-protocol into the
// hardhat compile graph so `deploy.ts` can `getContractFactory("SemaphoreVerifier")`
// when `USE_REAL_VERIFIER=true`. Nothing else under ./contracts/ imports the
// concrete verifier — `Semaphore` takes it as a constructor address — so without
// this side-effect import the artifact is never produced. This file declares no
// contract of its own.
import "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol";
