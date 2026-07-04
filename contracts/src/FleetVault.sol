// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MachineRegistry} from "./MachineRegistry.sol";

/// @title FleetVault
/// @notice The treasury of a fleet: revenue earned by the fleet's machines is
///         deposited here with per-machine attribution, producing a verifiable
///         onchain P&L for every robot, and is distributed to beneficiaries
///         (operator, financiers, crew) by fixed basis-point splits.
///
///         This per-machine earnings history is the dataset that later phases
///         (fleet financing, insurance underwriting) price against.
contract FleetVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------- types

    struct Beneficiary {
        address account;
        uint16 bps;
    }

    // -------------------------------------------------------------- storage

    MachineRegistry public immutable REGISTRY;
    IERC20 public immutable ASSET; // canonically USDC
    address public operator;

    Beneficiary[] internal _beneficiaries;

    mapping(uint256 mid => bool) public inFleet;
    mapping(uint256 mid => uint256) public machineRevenue; // lifetime, attributed
    uint256 public totalRevenue;
    uint256 public undistributed;
    mapping(address account => uint256) public claimable;

    uint16 public constant TOTAL_BPS = 10_000;

    // --------------------------------------------------------------- events

    event MachineAdded(uint256 indexed mid);
    event MachineRemoved(uint256 indexed mid);
    event RevenueDeposited(uint256 indexed mid, address indexed from, uint256 amount);
    event Distributed(uint256 amount);
    event Claimed(address indexed account, uint256 amount);
    event BeneficiariesSet(uint256 count);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    // --------------------------------------------------------------- errors

    error NotOperator();
    error NotFleetMachine(uint256 mid);
    error NotMachineOperator(uint256 mid);
    error BadSplits();
    error ZeroAmount();
    error ZeroAddress();
    error NothingToClaim();

    // ---------------------------------------------------------- constructor

    /// @param beneficiaries Split table; bps must sum to exactly 10_000.
    constructor(MachineRegistry registry, IERC20 asset, address operator_, Beneficiary[] memory beneficiaries) {
        if (operator_ == address(0)) revert ZeroAddress();
        REGISTRY = registry;
        ASSET = asset;
        operator = operator_;
        _setBeneficiaries(beneficiaries);
    }

    // ------------------------------------------------------------ modifiers

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    // ------------------------------------------------------- fleet membership

    /// @notice Enroll a machine. The vault operator must be the machine's operator
    ///         in the MachineRegistry, so revenue cannot be attributed to machines
    ///         the fleet does not control.
    function addMachine(uint256 mid) external onlyOperator {
        if (REGISTRY.ownerOf(mid) != operator) revert NotMachineOperator(mid);
        inFleet[mid] = true;
        emit MachineAdded(mid);
    }

    function removeMachine(uint256 mid) external onlyOperator {
        inFleet[mid] = false;
        emit MachineRemoved(mid);
    }

    // ---------------------------------------------------------------- revenue

    /// @notice Deposit revenue attributed to a fleet machine. Callable by anyone
    ///         (payers, gateways, the machine's own account); attribution is what
    ///         matters, and it is restricted to enrolled machines.
    function deposit(uint256 mid, uint256 amount) external nonReentrant {
        if (!inFleet[mid]) revert NotFleetMachine(mid);
        if (amount == 0) revert ZeroAmount();

        ASSET.safeTransferFrom(msg.sender, address(this), amount);
        machineRevenue[mid] += amount;
        totalRevenue += amount;
        undistributed += amount;
        emit RevenueDeposited(mid, msg.sender, amount);
    }

    /// @notice Allocate all undistributed revenue to beneficiaries per the split
    ///         table. Funds become individually claimable (pull pattern).
    function distribute() public {
        uint256 amount = undistributed;
        if (amount == 0) return;
        undistributed = 0;

        uint256 allocated;
        uint256 n = _beneficiaries.length;
        for (uint256 i = 0; i < n; i++) {
            Beneficiary memory b = _beneficiaries[i];
            // Last beneficiary absorbs rounding dust so allocation always sums.
            uint256 share = i == n - 1 ? amount - allocated : (amount * b.bps) / TOTAL_BPS;
            claimable[b.account] += share;
            allocated += share;
        }
        emit Distributed(amount);
    }

    function claim() external nonReentrant {
        distribute();
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimable[msg.sender] = 0;
        ASSET.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // ----------------------------------------------------------------- admin

    /// @notice Replace the split table. Distributes pending revenue first so past
    ///         earnings settle under the splits they accrued under.
    function setBeneficiaries(Beneficiary[] memory beneficiaries) external onlyOperator {
        distribute();
        delete _beneficiaries;
        _setBeneficiaries(beneficiaries);
    }

    function transferOperator(address newOperator) external onlyOperator {
        if (newOperator == address(0)) revert ZeroAddress();
        emit OperatorTransferred(operator, newOperator);
        operator = newOperator;
    }

    // ----------------------------------------------------------------- views

    function beneficiaries() external view returns (Beneficiary[] memory) {
        return _beneficiaries;
    }

    // ------------------------------------------------------------- internals

    function _setBeneficiaries(Beneficiary[] memory list) internal {
        if (list.length == 0) revert BadSplits();
        uint256 sum;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].account == address(0)) revert ZeroAddress();
            if (list[i].bps == 0) revert BadSplits();
            sum += list[i].bps;
            _beneficiaries.push(list[i]);
        }
        if (sum != TOTAL_BPS) revert BadSplits();
        emit BeneficiariesSet(list.length);
    }
}
