# Retired ZK Voting / Airdrop Workflow

This document used to describe the old `ZkVoting.sol` and `ZkAirdrop.sol`
smart-contract prototype.

That architecture is no longer active. The current Tessera product is a
self-hosted verifiable bulletin board:

- no voting smart contracts;
- no airdrop contract;
- no local chain for the default demo;
- no relayer;
- no Semaphore/Groth16 proof path in the 1.0-critical product.

Use these current references instead:

- [`README.md`](README.md) for the product overview.
- [`INSTRUCTIONS.md`](INSTRUCTIONS.md) for the local demo flow.
- [`codes/README.md`](codes/README.md) for the implementation workspace.
- [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
  for the current architecture.
- [`docs/architecture/module-airdrop.md`](docs/architecture/module-airdrop.md)
  for the retired airdrop note.

Historical contract details are preserved in git history only and should not be
used as implementation guidance for current work.
