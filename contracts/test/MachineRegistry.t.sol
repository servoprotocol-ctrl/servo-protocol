// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";

contract MachineRegistryTest is Test {
    MachineRegistry registry;

    address gov = makeAddr("gov");
    address operator = makeAddr("operator");
    address attestor = makeAddr("attestor");

    uint256 machinePk;
    address machineKey;

    function setUp() public {
        registry = new MachineRegistry(gov);
        (machineKey, machinePk) = makeAddrAndKey("machineKey");
    }

    // ------------------------------------------------------------- helpers

    function _register() internal returns (uint256 mid) {
        vm.prank(operator);
        mid = registry.registerMachine(
            operator, keccak256("robot-serial-001"), MachineRegistry.MachineClass.MobileGround, "ipfs://meta"
        );
    }

    function _bindingSig(uint256 mid, address op, uint256 pk, address key) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(registry.KEY_BINDING_TYPEHASH(), mid, op, key));
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256(
                            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                        ),
                        keccak256(bytes("ServoMachineRegistry")),
                        keccak256(bytes("1")),
                        block.chainid,
                        address(registry)
                    )
                ),
                structHash
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _bind(uint256 mid) internal {
        bytes memory sig = _bindingSig(mid, operator, machinePk, machineKey);
        vm.prank(operator);
        registry.bindMachineKey(mid, machineKey, sig);
    }

    // --------------------------------------------------------------- tests

    function test_registerMachine() public {
        uint256 mid = _register();

        assertEq(mid, 1);
        assertEq(registry.ownerOf(mid), operator);
        assertEq(registry.midByHardwareHash(keccak256("robot-serial-001")), mid);
        assertTrue(registry.isActive(mid));

        MachineRegistry.Machine memory m = registry.getMachine(mid);
        assertEq(uint8(m.status), uint8(MachineRegistry.MachineStatus.Active));
        assertEq(uint8(m.class_), uint8(MachineRegistry.MachineClass.MobileGround));
        assertEq(m.metadataURI, "ipfs://meta");
    }

    function test_registerMachine_revertsOnDuplicateHardware() public {
        _register();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                MachineRegistry.HardwareAlreadyRegistered.selector, keccak256("robot-serial-001")
            )
        );
        registry.registerMachine(
            operator, keccak256("robot-serial-001"), MachineRegistry.MachineClass.Aerial, "ipfs://other"
        );
    }

    function test_bindMachineKey() public {
        uint256 mid = _register();
        _bind(mid);

        assertEq(registry.machineKeyOf(mid), machineKey);
        assertEq(registry.midByMachineKey(machineKey), mid);
    }

    function test_bindMachineKey_revertsOnBadSignature() public {
        uint256 mid = _register();
        (, uint256 wrongPk) = makeAddrAndKey("wrongKey");
        bytes memory sig = _bindingSig(mid, operator, wrongPk, machineKey);

        vm.prank(operator);
        vm.expectRevert(MachineRegistry.InvalidKeyBindingSignature.selector);
        registry.bindMachineKey(mid, machineKey, sig);
    }

    function test_bindMachineKey_onlyOperator() public {
        uint256 mid = _register();
        bytes memory sig = _bindingSig(mid, operator, machinePk, machineKey);

        vm.prank(makeAddr("rando"));
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.NotOperator.selector, mid));
        registry.bindMachineKey(mid, machineKey, sig);
    }

    function test_rebind_revokesOldKey() public {
        uint256 mid = _register();
        _bind(mid);

        (address newKey, uint256 newPk) = makeAddrAndKey("newMachineKey");
        bytes memory sig = _bindingSig(mid, operator, newPk, newKey);
        vm.prank(operator);
        registry.bindMachineKey(mid, newKey, sig);

        assertEq(registry.machineKeyOf(mid), newKey);
        assertEq(registry.midByMachineKey(machineKey), 0);
        assertEq(registry.midByMachineKey(newKey), mid);
    }

    function test_pauseAndUnpause() public {
        uint256 mid = _register();

        vm.prank(operator);
        registry.pauseMachine(mid);
        assertFalse(registry.isActive(mid));
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.MachineNotActive.selector, mid));
        registry.requireActive(mid);

        vm.prank(operator);
        registry.unpauseMachine(mid);
        assertTrue(registry.isActive(mid));
    }

    function test_decommission_isTerminal() public {
        uint256 mid = _register();
        _bind(mid);

        vm.prank(operator);
        registry.decommissionMachine(mid);

        assertFalse(registry.isActive(mid));
        assertEq(registry.machineKeyOf(mid), address(0));
        assertEq(registry.midByMachineKey(machineKey), 0);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.MachineDecommissioned.selector, mid));
        registry.unpauseMachine(mid);
    }

    function test_transfer_revokesMachineKey() public {
        uint256 mid = _register();
        _bind(mid);

        address buyer = makeAddr("buyer");
        vm.prank(operator);
        registry.transferFrom(operator, buyer, mid);

        assertEq(registry.ownerOf(mid), buyer);
        assertEq(registry.machineKeyOf(mid), address(0));
        assertEq(registry.midByMachineKey(machineKey), 0);
    }

    function test_attest_isEventOnly_doesNotTouchFinancialRecord() public {
        uint256 mid = _register();

        vm.prank(gov);
        registry.setAttestor(attestor, true);

        // Attestations publish non-financial records (e.g. uptime) and must NOT
        // move the machine's revenue or job counters.
        vm.prank(attestor);
        registry.attest(mid, keccak256("UPTIME_EPOCH"), 86_400, keccak256("evidence"));

        MachineRegistry.Machine memory m = registry.getMachine(mid);
        assertEq(m.jobsAttested, 0);
        assertEq(m.revenueAttested, 0);
    }

    function test_attest_revertsForNonAttestor() public {
        uint256 mid = _register();
        vm.prank(makeAddr("rando"));
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.NotAttestor.selector, makeAddr("rando")));
        registry.attest(mid, keccak256("UPTIME_EPOCH"), 1, bytes32(0));
    }

    function test_recordCommerce_onlyRecorder() public {
        uint256 mid = _register();

        // A non-recorder (even an authorized attestor) cannot write the P&L.
        vm.prank(gov);
        registry.setAttestor(attestor, true);
        vm.prank(attestor);
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.NotRecorder.selector, attestor));
        registry.recordCommerce(mid, 25e6);

        // An authorized recorder writes revenue and increments the job count.
        address recorder = makeAddr("recorder");
        vm.prank(gov);
        registry.setRecorder(recorder, true);
        vm.startPrank(recorder);
        registry.recordCommerce(mid, 5e6);
        registry.recordCommerce(mid, 7e6);
        vm.stopPrank();

        MachineRegistry.Machine memory m = registry.getMachine(mid);
        assertEq(m.revenueAttested, 12e6);
        assertEq(m.jobsAttested, 2);
    }
}
