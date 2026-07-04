// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MachineRegistry} from "./MachineRegistry.sol";
import {ServiceRegistry} from "./ServiceRegistry.sol";

/// @title MachineAccount
/// @notice The bank account of a single machine. Funds are owned by the operator;
///         the machine's bound session key may spend them only inside an
///         operator-defined policy envelope:
///
///           - per-token daily spend caps,
///           - an optional counterparty allowlist,
///           - a hard pause (kill switch), and
///           - the machine must be Active in the MachineRegistry.
///
///         The operator (current owner of the MID) retains unrestricted control.
///         Payments made through `purchase` settle against the ServiceRegistry so
///         every machine-to-machine trade leaves an onchain receipt.
contract MachineAccount is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------- types

    struct Policy {
        bool allowlistEnabled;
        bool paused;
        mapping(address token => uint256) dailyCap; // 0 = token not spendable by machine
        mapping(address counterparty => bool) allowed;
    }

    // -------------------------------------------------------------- storage

    MachineRegistry public immutable REGISTRY;
    ServiceRegistry public immutable SERVICES;
    uint256 public immutable MID;

    Policy internal _policy;

    /// @notice epoch (day number) => token => amount spent by the machine key.
    mapping(uint256 epoch => mapping(address token => uint256)) public spentInEpoch;

    // --------------------------------------------------------------- events

    event MachinePayment(address indexed token, address indexed to, uint256 amount, bytes32 indexed memo);
    event ServicePurchased(uint256 indexed serviceId, address indexed token, uint256 amount);
    event DailyCapSet(address indexed token, uint256 cap);
    event AllowlistEnabled(bool enabled);
    event CounterpartySet(address indexed counterparty, bool allowed);
    event AccountPaused(bool paused);
    event OperatorExecuted(address indexed target, uint256 value, bytes data);
    event Deposited(address indexed from, uint256 amount);

    // --------------------------------------------------------------- errors

    error NotOperator();
    error NotMachineKey();
    error AccountIsPaused();
    error TokenNotSpendable(address token);
    error DailyCapExceeded(address token, uint256 attempted, uint256 remaining);
    error CounterpartyNotAllowed(address counterparty);
    error ExecutionFailed();

    // ---------------------------------------------------------- constructor

    constructor(MachineRegistry registry, ServiceRegistry services, uint256 mid) {
        REGISTRY = registry;
        SERVICES = services;
        MID = mid;
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // ------------------------------------------------------------ modifiers

    modifier onlyOperator() {
        if (msg.sender != REGISTRY.ownerOf(MID)) revert NotOperator();
        _;
    }

    modifier onlyMachineKey() {
        if (msg.sender != REGISTRY.machineKeyOf(MID)) revert NotMachineKey();
        REGISTRY.requireActive(MID);
        if (_policy.paused) revert AccountIsPaused();
        _;
    }

    // -------------------------------------------------- machine-key spending

    /// @notice Machine-initiated payment, constrained by policy. This is the path a
    ///         robot uses to pay for charging, tolls, data, or peer services when the
    ///         counterparty is not listed in the ServiceRegistry.
    function pay(address token, address to, uint256 amount, bytes32 memo) external onlyMachineKey nonReentrant {
        _checkAndConsume(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
        emit MachinePayment(token, to, amount, memo);
    }

    /// @notice Machine-initiated purchase of a registered service. Settlement runs
    ///         through the ServiceRegistry so the trade emits a canonical receipt and
    ///         updates both sides' commerce stats.
    function purchase(uint256 serviceId) external onlyMachineKey nonReentrant {
        (address token, address payTo, uint256 price) = SERVICES.quote(serviceId);
        _checkAndConsume(token, payTo, price);
        IERC20(token).forceApprove(address(SERVICES), price);
        SERVICES.purchase(serviceId, MID);
        emit ServicePurchased(serviceId, token, price);
    }

    // ------------------------------------------------------ operator control

    /// @notice Unrestricted operator escape hatch: withdraw, rescue, integrate.
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyOperator
        nonReentrant
        returns (bytes memory result)
    {
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert ExecutionFailed();
        emit OperatorExecuted(target, value, data);
    }

    function setDailyCap(address token, uint256 cap) external onlyOperator {
        _policy.dailyCap[token] = cap;
        emit DailyCapSet(token, cap);
    }

    function setAllowlistEnabled(bool enabled) external onlyOperator {
        _policy.allowlistEnabled = enabled;
        emit AllowlistEnabled(enabled);
    }

    function setCounterparty(address counterparty, bool allowed) external onlyOperator {
        _policy.allowed[counterparty] = allowed;
        emit CounterpartySet(counterparty, allowed);
    }

    /// @notice Account-level kill switch (independent of the registry-level pause).
    function setPaused(bool paused) external onlyOperator {
        _policy.paused = paused;
        emit AccountPaused(paused);
    }

    // ----------------------------------------------------------------- views

    function currentEpoch() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function dailyCap(address token) external view returns (uint256) {
        return _policy.dailyCap[token];
    }

    function remainingToday(address token) public view returns (uint256) {
        uint256 cap = _policy.dailyCap[token];
        uint256 spent = spentInEpoch[currentEpoch()][token];
        return spent >= cap ? 0 : cap - spent;
    }

    function allowlistEnabled() external view returns (bool) {
        return _policy.allowlistEnabled;
    }

    function isCounterpartyAllowed(address counterparty) external view returns (bool) {
        return _policy.allowed[counterparty];
    }

    function paused() external view returns (bool) {
        return _policy.paused;
    }

    // ------------------------------------------------------------- internals

    function _checkAndConsume(address token, address counterparty, uint256 amount) internal {
        uint256 cap = _policy.dailyCap[token];
        if (cap == 0) revert TokenNotSpendable(token);
        if (_policy.allowlistEnabled && !_policy.allowed[counterparty]) {
            revert CounterpartyNotAllowed(counterparty);
        }
        uint256 epoch = currentEpoch();
        uint256 spent = spentInEpoch[epoch][token];
        if (spent + amount > cap) revert DailyCapExceeded(token, amount, cap - spent);
        spentInEpoch[epoch][token] = spent + amount;
    }
}
