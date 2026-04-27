// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";

contract PollRegistry {
    using Clones for address;

    struct PollInfo {
        address pollAddress;
        string moduleType;
        string title;
        string description;
        address creator;
        uint256 createdAt;
    }

    address public owner;
    mapping(string => address) public modules;
    PollInfo[] public polls;

    event ModuleRegistered(string moduleType, address implementation);
    event PollCreated(
        address pollAddress,
        string moduleType,
        string title,
        address creator
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Register (or update) a module implementation address
    function registerModule(
        string calldata moduleType,
        address implementation
    ) external onlyOwner {
        require(implementation != address(0), "Zero address");
        modules[moduleType] = implementation;
        emit ModuleRegistered(moduleType, implementation);
    }

    /// @notice Clone a registered module and initialize it
    /// @param moduleType  Key used in registerModule
    /// @param title       Human-readable poll title
    /// @param description Human-readable poll description
    /// @param initData    ABI-encoded call to the clone's initialize function
    function createPoll(
        string calldata moduleType,
        string calldata title,
        string calldata description,
        bytes calldata initData
    ) external returns (address) {
        address impl = modules[moduleType];
        require(impl != address(0), "Module not registered");

        address clone = impl.clone();

        // Initialize the clone
        (bool ok, ) = clone.call(initData);
        require(ok, "Init failed");

        polls.push(
            PollInfo({
                pollAddress: clone,
                moduleType: moduleType,
                title: title,
                description: description,
                creator: msg.sender,
                createdAt: block.timestamp
            })
        );

        emit PollCreated(clone, moduleType, title, msg.sender);
        return clone;
    }

    function getPollCount() external view returns (uint256) {
        return polls.length;
    }

    function getAllPolls() external view returns (PollInfo[] memory) {
        return polls;
    }
}
