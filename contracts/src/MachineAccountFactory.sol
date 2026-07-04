// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MachineRegistry} from "./MachineRegistry.sol";
import {ServiceRegistry} from "./ServiceRegistry.sol";
import {MachineAccount} from "./MachineAccount.sol";

/// @title MachineAccountFactory
/// @notice Deploys one canonical MachineAccount per MID and indexes it, so any
///         counterparty can resolve a machine's bank account from its identity.
contract MachineAccountFactory {
    MachineRegistry public immutable REGISTRY;
    ServiceRegistry public immutable SERVICES;

    mapping(uint256 mid => address account) public accountOf;

    event MachineAccountCreated(uint256 indexed mid, address indexed account, address indexed operator);

    error NotOperator(uint256 mid);
    error AccountExists(uint256 mid);

    constructor(MachineRegistry registry, ServiceRegistry services) {
        REGISTRY = registry;
        SERVICES = services;
    }

    function createAccount(uint256 mid) external returns (address account) {
        if (REGISTRY.ownerOf(mid) != msg.sender) revert NotOperator(mid);
        if (accountOf[mid] != address(0)) revert AccountExists(mid);

        account = address(new MachineAccount(REGISTRY, SERVICES, mid));
        accountOf[mid] = account;
        emit MachineAccountCreated(mid, account, msg.sender);
    }
}
