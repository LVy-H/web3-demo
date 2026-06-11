// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Errors for {PollRegistry}.
/// @dev OZ-provided errors (OwnableUnauthorizedAccount, OwnableInvalidOwner) cover
///      the access-control reverts; these are the registry's local errors.
error ZeroAddress();
error ModuleNotRegistered(string moduleType);
error InitFailed();
error InvalidVisibility(uint8 visibility);
error UnknownPoll(address pollAddress);

contract PollRegistry is Ownable2Step {
    using Clones for address;

    /// @notice Discovery visibility of a poll (R4 privacy defaults).
    ///         0 = UNLISTED (default): the poll is link-access only — it is NOT
    ///             returned by {getListedPolls}, the public-directory view.
    ///         1 = LISTED: an explicit creation-time opt-in to public discovery.
    /// @dev This is DISCOVERY privacy, not content privacy: all chain data is
    ///      public, so anyone who learns a poll's address (or scans PollCreated
    ///      events / the `polls` array) can still read everything. The flag's
    ///      job is to keep compliant directories (clients, indexers) from
    ///      presenting unlisted polls — the link/QR/code is the capability.
    uint8 public constant VISIBILITY_UNLISTED = 0;
    uint8 public constant VISIBILITY_LISTED = 1;

    struct PollInfo {
        address pollAddress;
        string moduleType;
        string title;
        string description;
        address creator;
        uint256 createdAt;
        /// @dev 0 = unlisted (default), 1 = listed. Appended last so the leading
        ///      field order stays stable for existing positional decoders.
        uint8 visibility;
    }

    mapping(string => address) public modules;
    PollInfo[] public polls;

    /// @dev pollAddress => index in `polls` + 1 (0 = unknown). Lets unlisted
    ///      polls be fetched BY ADDRESS (link-access model) via {getPollInfo}.
    mapping(address => uint256) private pollIndexPlusOne;

    event ModuleRegistered(string moduleType, address implementation);
    event PollCreated(
        address pollAddress,
        string moduleType,
        string title,
        address creator,
        uint8 visibility
    );

    constructor() Ownable(msg.sender) {}

    /// @notice Register (or update) a module implementation address
    function registerModule(string calldata moduleType, address implementation) external onlyOwner {
        if (implementation == address(0)) revert ZeroAddress();
        modules[moduleType] = implementation;
        emit ModuleRegistered(moduleType, implementation);
    }

    /// @notice Clone a registered module and initialize it. UNLISTED by default:
    ///         this overload exists so the private-by-default choice is made by
    ///         the contract, not by every caller remembering a flag (R4 spec §3
    ///         principle 1). Use the 5-arg overload to opt in to public listing.
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
        return _createPoll(moduleType, title, description, VISIBILITY_UNLISTED, initData);
    }

    /// @notice Clone a registered module and initialize it, with an explicit
    ///         discovery visibility (R4 privacy defaults).
    /// @param moduleType  Key used in registerModule
    /// @param title       Human-readable poll title
    /// @param description Human-readable poll description
    /// @param visibility  0 = unlisted (link-access only), 1 = listed (public
    ///                    directory opt-in). Any other value reverts.
    /// @param initData    ABI-encoded call to the clone's initialize function
    function createPoll(
        string calldata moduleType,
        string calldata title,
        string calldata description,
        uint8 visibility,
        bytes calldata initData
    ) external returns (address) {
        return _createPoll(moduleType, title, description, visibility, initData);
    }

    function _createPoll(
        string calldata moduleType,
        string calldata title,
        string calldata description,
        uint8 visibility,
        bytes calldata initData
    ) internal returns (address) {
        if (visibility > VISIBILITY_LISTED) revert InvalidVisibility(visibility);

        address impl = modules[moduleType];
        if (impl == address(0)) revert ModuleNotRegistered(moduleType);

        address clone = impl.clone();

        // Initialize the clone
        (bool ok, ) = clone.call(initData);
        if (!ok) revert InitFailed();

        polls.push(
            PollInfo({
                pollAddress: clone,
                moduleType: moduleType,
                title: title,
                description: description,
                creator: msg.sender,
                createdAt: block.timestamp,
                visibility: visibility
            })
        );
        pollIndexPlusOne[clone] = polls.length;

        emit PollCreated(clone, moduleType, title, msg.sender, visibility);
        return clone;
    }

    function getPollCount() external view returns (uint256) {
        return polls.length;
    }

    /// @notice Return EVERY poll, listed and unlisted.
    /// @dev OWNER/OPS COMPAT ONLY. Public directories (browse screens, indexers)
    ///      MUST use {getListedPolls} instead — surfacing unlisted polls in a
    ///      directory defeats the link-access model. This stays callable by
    ///      anyone because chain data is public anyway (see {VISIBILITY_UNLISTED});
    ///      restricting it on-chain would be security theater, not privacy.
    function getAllPolls() external view returns (PollInfo[] memory) {
        return polls;
    }

    /// @notice Return only the polls that opted in to public listing
    ///         (visibility == 1). This is THE view for public poll directories.
    function getListedPolls() external view returns (PollInfo[] memory) {
        uint256 listedCount = 0;
        for (uint256 i = 0; i < polls.length; i++) {
            if (polls[i].visibility == VISIBILITY_LISTED) listedCount++;
        }

        PollInfo[] memory listed = new PollInfo[](listedCount);
        uint256 j = 0;
        for (uint256 i = 0; i < polls.length; i++) {
            if (polls[i].visibility == VISIBILITY_LISTED) {
                listed[j] = polls[i];
                j++;
            }
        }
        return listed;
    }

    /// @notice Fetch one poll's registry info by its address — the link-access
    ///         path. Works for unlisted polls too: whoever holds the poll's
    ///         address (from a link/QR/code) can resolve its metadata without
    ///         the poll ever appearing in a directory.
    /// @dev Reverts with {UnknownPoll} for addresses this registry didn't create.
    function getPollInfo(address pollAddress) external view returns (PollInfo memory) {
        uint256 idxPlusOne = pollIndexPlusOne[pollAddress];
        if (idxPlusOne == 0) revert UnknownPoll(pollAddress);
        return polls[idxPlusOne - 1];
    }
}
