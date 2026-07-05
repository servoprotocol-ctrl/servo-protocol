// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title MachineRegistry
/// @notice The identity root of the Servo protocol: every machine (robot, drone,
///         autonomous vehicle, embedded device) is issued a Machine ID (MID) as an
///         ERC-721 token owned by its operator.
///
///         A MID binds together:
///           1. The operator (token owner) who is legally and economically responsible.
///           2. A hardware identity commitment (hash of the device's secure-element
///              public key / serial attestation), unique across the registry.
///           3. An onchain machine key: a session address held by the device itself,
///              proven via an EIP-712 signature, used to transact from its MachineAccount.
///           4. A service record: attestations (jobs completed, uptime, revenue) written
///              by authorized attestors, forming the machine's verifiable work history.
///
///         "Know Your Machine": counterparties, vaults, insurers, and financiers all
///         resolve machines through this contract.
contract MachineRegistry is ERC721, Ownable, EIP712 {
    // ---------------------------------------------------------------- types

    enum MachineStatus {
        None,
        Active,
        Paused,
        Decommissioned
    }

    enum MachineClass {
        Unspecified,
        Humanoid,
        MobileGround,
        Aerial,
        Manipulator,
        Vehicle,
        Stationary,
        Virtual
    }

    struct Machine {
        MachineStatus status;
        MachineClass class_;
        address machineKey; // session key held by the device, zero if unbound
        bytes32 hardwareHash; // commitment to the device's hardware identity
        uint64 registeredAt;
        uint64 jobsAttested;
        uint128 revenueAttested; // cumulative revenue reported by attestors (USDC 6dp)
        string metadataURI;
    }

    // -------------------------------------------------------------- storage

    uint256 public nextMid = 1;

    mapping(uint256 mid => Machine) internal _machines;
    mapping(bytes32 hardwareHash => uint256 mid) public midByHardwareHash;
    mapping(address machineKey => uint256 mid) public midByMachineKey;
    mapping(address attestor => bool) public isAttestor;
    /// @notice Recorders (canonically the ServiceRegistry) are the ONLY writers of the
    ///         financial service record. Revenue and job counts are therefore derived
    ///         from real onchain settlement, not from arbitrary attestor input.
    mapping(address recorder => bool) public isRecorder;

    bytes32 public constant KEY_BINDING_TYPEHASH =
        keccak256("KeyBinding(uint256 mid,address operator,address machineKey)");

    // --------------------------------------------------------------- events

    event MachineRegistered(
        uint256 indexed mid, address indexed operator, bytes32 indexed hardwareHash, MachineClass class_
    );
    event MachineKeyBound(uint256 indexed mid, address indexed machineKey);
    event MachineKeyRevoked(uint256 indexed mid, address indexed machineKey);
    event MachineStatusChanged(uint256 indexed mid, MachineStatus status);
    event MachineAttested(
        uint256 indexed mid, address indexed attestor, bytes32 indexed kind, uint256 value, bytes32 dataHash
    );
    event AttestorSet(address indexed attestor, bool allowed);
    event RecorderSet(address indexed recorder, bool allowed);
    event CommerceRecorded(uint256 indexed mid, address indexed recorder, uint256 revenue, uint256 jobs);
    event MetadataURIUpdated(uint256 indexed mid, string uri);

    // --------------------------------------------------------------- errors

    error HardwareAlreadyRegistered(bytes32 hardwareHash);
    error MachineKeyAlreadyBound(address machineKey);
    error InvalidKeyBindingSignature();
    error NotRecorder(address caller);
    error NotOperator(uint256 mid);
    error NotAttestor(address caller);
    error MachineNotActive(uint256 mid);
    error MachineDecommissioned(uint256 mid);
    error ZeroAddress();
    error ZeroHardwareHash();

    // ---------------------------------------------------------- constructor

    constructor(address initialOwner)
        ERC721("Servo Machine ID", "MID")
        Ownable(initialOwner)
        EIP712("ServoMachineRegistry", "1")
    {}

    // ------------------------------------------------------------ modifiers

    modifier onlyOperator(uint256 mid) {
        if (_ownerOf(mid) != msg.sender) revert NotOperator(mid);
        _;
    }

    // ----------------------------------------------------------- registration

    /// @notice Register a new machine and mint its MID to `operator`.
    /// @param operator     Address that owns and is responsible for the machine.
    /// @param hardwareHash Commitment to the device hardware identity (e.g. keccak256
    ///                     of the secure-element public key). Must be globally unique.
    /// @param class_       Coarse machine classification.
    /// @param metadataURI  Offchain metadata (make, model, specs, images).
    function registerMachine(address operator, bytes32 hardwareHash, MachineClass class_, string calldata metadataURI)
        external
        returns (uint256 mid)
    {
        if (operator == address(0)) revert ZeroAddress();
        if (hardwareHash == bytes32(0)) revert ZeroHardwareHash();
        if (midByHardwareHash[hardwareHash] != 0) revert HardwareAlreadyRegistered(hardwareHash);

        mid = nextMid++;
        _machines[mid] = Machine({
            status: MachineStatus.Active,
            class_: class_,
            machineKey: address(0),
            hardwareHash: hardwareHash,
            registeredAt: uint64(block.timestamp),
            jobsAttested: 0,
            revenueAttested: 0,
            metadataURI: metadataURI
        });
        midByHardwareHash[hardwareHash] = mid;

        _safeMint(operator, mid);
        emit MachineRegistered(mid, operator, hardwareHash, class_);
    }

    /// @notice Bind the device's onchain session key to its MID. The device proves
    ///         possession of the key by signing an EIP-712 KeyBinding message.
    function bindMachineKey(uint256 mid, address machineKey, bytes calldata signature) external onlyOperator(mid) {
        if (machineKey == address(0)) revert ZeroAddress();
        if (midByMachineKey[machineKey] != 0) revert MachineKeyAlreadyBound(machineKey);
        Machine storage m = _machines[mid];
        if (m.status == MachineStatus.Decommissioned) revert MachineDecommissioned(mid);

        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(KEY_BINDING_TYPEHASH, mid, msg.sender, machineKey)));
        if (ECDSA.recover(digest, signature) != machineKey) revert InvalidKeyBindingSignature();

        // Revoke a previously bound key, if any.
        address old = m.machineKey;
        if (old != address(0)) {
            delete midByMachineKey[old];
            emit MachineKeyRevoked(mid, old);
        }

        m.machineKey = machineKey;
        midByMachineKey[machineKey] = mid;
        emit MachineKeyBound(mid, machineKey);
    }

    /// @notice Revoke the machine's session key (e.g. suspected compromise).
    function revokeMachineKey(uint256 mid) external onlyOperator(mid) {
        _revokeKey(mid);
    }

    // -------------------------------------------------------------- lifecycle

    /// @notice Operator kill switch: pause a machine. Paused machines fail
    ///         `requireActive` checks across the protocol (payments, purchases).
    function pauseMachine(uint256 mid) external onlyOperator(mid) {
        Machine storage m = _machines[mid];
        if (m.status == MachineStatus.Decommissioned) revert MachineDecommissioned(mid);
        m.status = MachineStatus.Paused;
        emit MachineStatusChanged(mid, MachineStatus.Paused);
    }

    function unpauseMachine(uint256 mid) external onlyOperator(mid) {
        Machine storage m = _machines[mid];
        if (m.status == MachineStatus.Decommissioned) revert MachineDecommissioned(mid);
        m.status = MachineStatus.Active;
        emit MachineStatusChanged(mid, MachineStatus.Active);
    }

    /// @notice Permanently retire a machine. Irreversible; the MID survives as a
    ///         historical record but can no longer transact.
    function decommissionMachine(uint256 mid) external onlyOperator(mid) {
        _machines[mid].status = MachineStatus.Decommissioned;
        _revokeKey(mid);
        emit MachineStatusChanged(mid, MachineStatus.Decommissioned);
    }

    function setMetadataURI(uint256 mid, string calldata uri) external onlyOperator(mid) {
        _machines[mid].metadataURI = uri;
        emit MetadataURIUpdated(mid, uri);
    }

    // ------------------------------------------------------------ attestation

    /// @notice Protocol governance authorizes attestors (oracles, audited fleet
    ///         software) that publish non-financial records such as uptime.
    function setAttestor(address attestor, bool allowed) external onlyOwner {
        if (attestor == address(0)) revert ZeroAddress();
        isAttestor[attestor] = allowed;
        emit AttestorSet(attestor, allowed);
    }

    /// @notice Governance authorizes recorders (canonically the ServiceRegistry)
    ///         that write the financial service record from settled commerce.
    function setRecorder(address recorder, bool allowed) external onlyOwner {
        if (recorder == address(0)) revert ZeroAddress();
        isRecorder[recorder] = allowed;
        emit RecorderSet(recorder, allowed);
    }

    /// @notice Publish a non-financial attestation (e.g. uptime, inspection pass).
    ///         Attestations are events only: they never mutate the machine's
    ///         revenue or job counters, so a rogue attestor cannot forge P&L.
    /// @param kind     Attestation type, e.g. keccak256("UPTIME_EPOCH").
    /// @param value    Numeric payload (e.g. seconds of uptime).
    /// @param dataHash Commitment to offchain evidence.
    function attest(uint256 mid, bytes32 kind, uint256 value, bytes32 dataHash) external {
        if (!isAttestor[msg.sender]) revert NotAttestor(msg.sender);
        _requireOwned(mid);
        emit MachineAttested(mid, msg.sender, kind, value, dataHash);
    }

    /// @notice Record settled commerce against a machine's P&L. Callable only by an
    ///         authorized recorder, and only from an actual onchain payment, so
    ///         revenueAttested is provable rather than asserted. Each call counts
    ///         one completed job.
    function recordCommerce(uint256 mid, uint256 revenue) external {
        if (!isRecorder[msg.sender]) revert NotRecorder(msg.sender);
        _requireOwned(mid);
        Machine storage m = _machines[mid];
        m.revenueAttested += SafeCast.toUint128(revenue);
        m.jobsAttested += 1;
        emit CommerceRecorded(mid, msg.sender, revenue, 1);
    }

    // ----------------------------------------------------------------- views

    function getMachine(uint256 mid) external view returns (Machine memory) {
        _requireOwned(mid);
        return _machines[mid];
    }

    function operatorOf(uint256 mid) external view returns (address) {
        return _requireOwned(mid);
    }

    function machineKeyOf(uint256 mid) external view returns (address) {
        _requireOwned(mid);
        return _machines[mid].machineKey;
    }

    function statusOf(uint256 mid) public view returns (MachineStatus) {
        _requireOwned(mid);
        return _machines[mid].status;
    }

    function isActive(uint256 mid) public view returns (bool) {
        return _ownerOf(mid) != address(0) && _machines[mid].status == MachineStatus.Active;
    }

    /// @notice Revert helper used by MachineAccount and ServiceRegistry.
    function requireActive(uint256 mid) external view {
        if (!isActive(mid)) revert MachineNotActive(mid);
    }

    function tokenURI(uint256 mid) public view override returns (string memory) {
        _requireOwned(mid);
        return _machines[mid].metadataURI;
    }

    // ------------------------------------------------------------- internals

    function _revokeKey(uint256 mid) internal {
        Machine storage m = _machines[mid];
        address old = m.machineKey;
        if (old != address(0)) {
            delete midByMachineKey[old];
            m.machineKey = address(0);
            emit MachineKeyRevoked(mid, old);
        }
    }

    /// @dev On operator transfer (fleet sale, repossession) the machine session key
    ///      is revoked: the new operator must re-bind a key it controls.
    function _update(address to, uint256 mid, address auth) internal override returns (address from) {
        from = super._update(to, mid, auth);
        if (from != address(0) && to != address(0) && from != to) {
            _revokeKey(mid);
        }
    }
}
