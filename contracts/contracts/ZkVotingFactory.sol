// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./ZkVoting.sol";

contract ZkVotingFactory {
    struct PollContext {
        address pollAddress;
        string title;
        string description;
        uint256 createdAt;
    }

    PollContext[] public polls;
    address public semaphoreAddress;

    event PollCreated(
        address pollAddress,
        string title,
        string description,
        address owner
    );

    constructor(address _semaphoreAddress) {
        semaphoreAddress = _semaphoreAddress;
    }

    function createPoll(
        string calldata title,
        string calldata description
    ) external returns (address) {
        ZkVoting newPoll = new ZkVoting(semaphoreAddress, msg.sender);

        polls.push(
            PollContext({
                pollAddress: address(newPoll),
                title: title,
                description: description,
                createdAt: block.timestamp
            })
        );

        emit PollCreated(address(newPoll), title, description, msg.sender);

        return address(newPoll);
    }

    function getPollsCount() external view returns (uint256) {
        return polls.length;
    }

    function getAllPolls() external view returns (PollContext[] memory) {
        return polls;
    }
}
