// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IZkPoll {
    enum PollState {
        Registration,
        Voting,
        Ended
    }
    event StateChanged(PollState newState);

    function getState() external view returns (PollState);

    /// @notice Results-timing policy (R4 privacy defaults), fixed at initialize.
    ///         0 = sealed-until-close (DEFAULT): compliant clients and the relayer
    ///             do not present tallies while voting is open.
    ///         1 = live-public: explicit creation-time opt-in to live tallies.
    /// @dev v1 ENFORCEMENT NOTE: this is METADATA that compliant clients/relayer
    ///      honor — not a cryptographic seal. Ballots arrive as public calldata
    ///      and every node can recompute the running tally, so restricting
    ///      {getResults} on-chain would be security theater, not privacy;
    ///      getResults() deliberately stays unrestricted. Cryptographic sealing
    ///      (threshold/timelock decryption) is the R5 roadmap phase.
    function resultsPolicy() external view returns (uint8);

    function getResults() external view returns (uint256[] memory);
    function getOptions() external view returns (string[] memory);
    function getParticipantCount() external view returns (uint256);
    function owner() external view returns (address);
    function verifyParticipation(uint256 nullifierHash) external view returns (bool);
}
