// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IZkPoll {
    enum PollState {
        Registration,
        Voting,
        Ended
    }
    event StateChanged(PollState newState);

    function getState() external view returns (PollState);
    function getResults() external view returns (uint256[] memory);
    function getOptions() external view returns (string[] memory);
    function getParticipantCount() external view returns (uint256);
    function owner() external view returns (address);
    function verifyParticipation(uint256 nullifierHash) external view returns (bool);
}
