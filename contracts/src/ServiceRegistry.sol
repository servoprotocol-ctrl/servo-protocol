// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MachineRegistry} from "./MachineRegistry.sol";
import {FleetVault} from "./FleetVault.sol";

/// @title ServiceRegistry
/// @notice The machine commerce network: a discovery and settlement layer for
///         services that machines buy and sell, such as charging bays, map and
///         route data, compute bursts, sensor feeds, and task handoffs.
///
///         Services are priced in an ERC-20 (canonically USDC on Base) and can be
///         settled two ways:
///
///           1. Onchain: `purchase` pulls payment from the buyer (typically a
///              MachineAccount) and emits a canonical `ServiceReceipt`.
///           2. Offchain via x402: an HTTP 402 gateway settles the payment and an
///              authorized facilitator mirrors it onchain with
///              `recordExternalReceipt`, so x402 trades still build the same
///              onchain commerce history.
///
///         A protocol fee (bps) is skimmed on onchain settlement and forwarded to
///         the treasury.
contract ServiceRegistry is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------- types

    struct Service {
        address provider; // account that manages the listing
        address payTo; // destination of revenue (often a FleetVault)
        address token; // settlement asset
        uint96 price; // price per unit
        uint256 providerMid; // 0 if the provider is not itself a machine
        bool active;
        bool vaultSettlement; // if true, payTo is a FleetVault and settlement runs
        // through deposit() so revenue is attributed to providerMid
        bytes32 category; // e.g. keccak256("CHARGING"), keccak256("MAP_DATA")
        uint64 unitsSold;
        uint128 grossRevenue;
        string uri; // x402-compatible endpoint / metadata URI
    }

    // -------------------------------------------------------------- storage

    MachineRegistry public immutable REGISTRY;

    uint256 public nextServiceId = 1;
    mapping(uint256 serviceId => Service) internal _services;

    mapping(address facilitator => bool) public isFacilitator;

    address public treasury;
    uint16 public protocolFeeBps; // capped at MAX_FEE_BPS
    uint16 public constant MAX_FEE_BPS = 500; // 5%

    // --------------------------------------------------------------- events

    event ServiceRegistered(
        uint256 indexed serviceId,
        address indexed provider,
        uint256 indexed providerMid,
        bytes32 category,
        address token,
        uint96 price,
        string uri
    );
    event ServiceUpdated(uint256 indexed serviceId, address payTo, uint96 price, bool active, string uri);
    event ServiceReceipt(
        uint256 indexed serviceId,
        uint256 indexed buyerMid,
        uint256 indexed providerMid,
        address token,
        uint256 amount,
        uint256 fee,
        bool external_
    );
    event FacilitatorSet(address indexed facilitator, bool allowed);
    event ProtocolFeeSet(uint16 feeBps, address treasury);

    // --------------------------------------------------------------- errors

    error ServiceNotFound(uint256 serviceId);
    error ServiceNotActive(uint256 serviceId);
    error NotProvider(uint256 serviceId);
    error NotFacilitator(address caller);
    error FeeTooHigh(uint16 bps);
    error ZeroAddress();
    error ZeroPrice();
    error VaultSettlementNeedsMachine();

    // ---------------------------------------------------------- constructor

    constructor(MachineRegistry registry, address initialOwner, address treasury_) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        REGISTRY = registry;
        treasury = treasury_;
        protocolFeeBps = 100; // 1% default
    }

    // --------------------------------------------------------------- listing

    /// @notice List a service. If `providerMid` is nonzero the caller must be that
    ///         machine's operator or bound machine key, making the listing a
    ///         machine-provided service (a robot selling to other robots).
    function registerService(
        uint256 providerMid,
        address payTo,
        address token,
        uint96 price,
        bytes32 category,
        bool vaultSettlement,
        string calldata uri
    ) external returns (uint256 serviceId) {
        if (payTo == address(0) || token == address(0)) revert ZeroAddress();
        if (price == 0) revert ZeroPrice();
        if (vaultSettlement && providerMid == 0) revert VaultSettlementNeedsMachine();
        if (providerMid != 0) {
            address op = REGISTRY.ownerOf(providerMid);
            address key = REGISTRY.machineKeyOf(providerMid);
            if (msg.sender != op && msg.sender != key) revert NotProvider(0);
        }

        serviceId = nextServiceId++;
        _services[serviceId] = Service({
            provider: msg.sender,
            payTo: payTo,
            token: token,
            price: price,
            providerMid: providerMid,
            active: true,
            vaultSettlement: vaultSettlement,
            category: category,
            unitsSold: 0,
            grossRevenue: 0,
            uri: uri
        });
        emit ServiceRegistered(serviceId, msg.sender, providerMid, category, token, price, uri);
    }

    function updateService(uint256 serviceId, address payTo, uint96 price, bool active, string calldata uri)
        external
    {
        Service storage s = _service(serviceId);
        if (msg.sender != s.provider) revert NotProvider(serviceId);
        if (payTo == address(0)) revert ZeroAddress();
        if (price == 0) revert ZeroPrice();
        s.payTo = payTo;
        s.price = price;
        s.active = active;
        s.uri = uri;
        emit ServiceUpdated(serviceId, payTo, price, active, uri);
    }

    // ------------------------------------------------------------ settlement

    /// @notice Onchain settlement: pulls `price` from the caller, forwards revenue
    ///         to the provider's `payTo` minus the protocol fee, and emits the
    ///         canonical receipt. `buyerMid` of 0 denotes a non-machine buyer.
    function purchase(uint256 serviceId, uint256 buyerMid) external nonReentrant {
        Service storage s = _service(serviceId);
        if (!s.active) revert ServiceNotActive(serviceId);
        if (buyerMid != 0) REGISTRY.requireActive(buyerMid);
        if (s.providerMid != 0) REGISTRY.requireActive(s.providerMid);

        uint256 price = s.price;
        uint256 fee = (price * protocolFeeBps) / 10_000;

        IERC20 token = IERC20(s.token);
        if (s.vaultSettlement) {
            // Route through FleetVault.deposit so the sale is attributed to the
            // providing machine's onchain P&L.
            token.safeTransferFrom(msg.sender, address(this), price - fee);
            token.forceApprove(s.payTo, price - fee);
            FleetVault(s.payTo).deposit(s.providerMid, price - fee);
        } else {
            token.safeTransferFrom(msg.sender, s.payTo, price - fee);
        }
        if (fee > 0) token.safeTransferFrom(msg.sender, treasury, fee);

        s.unitsSold += 1;
        s.grossRevenue += SafeCast.toUint128(price);

        emit ServiceReceipt(serviceId, buyerMid, s.providerMid, s.token, price, fee, false);
    }

    /// @notice Mirror an x402-settled payment onchain. Only authorized facilitators
    ///         (gateway operators) may write external receipts; no funds move here.
    function recordExternalReceipt(uint256 serviceId, uint256 buyerMid, uint256 amount) external {
        if (!isFacilitator[msg.sender]) revert NotFacilitator(msg.sender);
        Service storage s = _service(serviceId);

        s.unitsSold += 1;
        s.grossRevenue += SafeCast.toUint128(amount);

        emit ServiceReceipt(serviceId, buyerMid, s.providerMid, s.token, amount, 0, true);
    }

    // ---------------------------------------------------------------- admin

    function setFacilitator(address facilitator, bool allowed) external onlyOwner {
        if (facilitator == address(0)) revert ZeroAddress();
        isFacilitator[facilitator] = allowed;
        emit FacilitatorSet(facilitator, allowed);
    }

    function setProtocolFee(uint16 feeBps, address treasury_) external onlyOwner {
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh(feeBps);
        if (treasury_ == address(0)) revert ZeroAddress();
        protocolFeeBps = feeBps;
        treasury = treasury_;
        emit ProtocolFeeSet(feeBps, treasury_);
    }

    // ----------------------------------------------------------------- views

    function getService(uint256 serviceId) external view returns (Service memory) {
        return _service(serviceId);
    }

    /// @notice Settlement quote used by MachineAccount.purchase.
    function quote(uint256 serviceId) external view returns (address token, address payTo, uint256 price) {
        Service storage s = _service(serviceId);
        if (!s.active) revert ServiceNotActive(serviceId);
        return (s.token, s.payTo, s.price);
    }

    // ------------------------------------------------------------- internals

    function _service(uint256 serviceId) internal view returns (Service storage s) {
        s = _services[serviceId];
        if (s.provider == address(0)) revert ServiceNotFound(serviceId);
    }
}
