// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {MachineAccountFactory} from "../src/MachineAccountFactory.sol";
import {MachineAccount} from "../src/MachineAccount.sol";

/// @notice Seeds the live Base mainnet deployment with the first machines and the
///         first service (the "genesis" dogfood). Gas-only: no USDC required.
///
///   MACHINE_PK=<demo session key> forge script script/Dogfood.s.sol \
///     --rpc-url base --account servo-deployer --broadcast
contract Dogfood is Script {
    // Base mainnet deployment (see DEPLOYMENTS.md).
    MachineRegistry constant REG = MachineRegistry(0x78A6DfC16BD166f86F0263B1Eec3c697372d8ab6);
    ServiceRegistry constant SVC = ServiceRegistry(0x7896Dba19A72278d66C9f0640262C511D24CB871);
    MachineAccountFactory constant FAC = MachineAccountFactory(0x24f2f3536F65CA2AE36136E3B217a390251a1a90);
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        address operator = msg.sender;
        uint256 machinePk = vm.envUint("MACHINE_PK");
        address machineKey = vm.addr(machinePk);

        vm.startBroadcast();

        // --- Genesis machine #1: a charging station (service provider).
        uint256 chargerMid = REG.registerMachine(
            operator,
            keccak256("servo-genesis-charger-001"),
            MachineRegistry.MachineClass.Stationary,
            "https://servoprotocol.xyz/m/1"
        );

        // --- Genesis machine #2: a delivery bot (the buyer) with a bank account.
        uint256 botMid = REG.registerMachine(
            operator,
            keccak256("servo-genesis-bot-001"),
            MachineRegistry.MachineClass.MobileGround,
            "https://servoprotocol.xyz/m/2"
        );
        address botAccount = FAC.createAccount(botMid);

        // Bind the bot's device session key (signed proof of possession).
        bytes memory sig = _bindingSig(machinePk, botMid, operator, machineKey);
        REG.bindMachineKey(botMid, machineKey, sig);

        // Operator sets the policy envelope: 5 USDC/day spend cap.
        MachineAccount(payable(botAccount)).setDailyCap(USDC, 5e6);

        // --- Genesis service: charging, sold by the station, priced in USDC.
        uint256 serviceId = SVC.registerService(
            chargerMid,
            operator, // payTo (revenue destination) for this first listing
            USDC,
            0.05e6, // 0.05 USDC per session
            keccak256("CHARGING"),
            false, // direct settlement (still records provider P&L)
            "https://servoprotocol.xyz/svc/1"
        );

        vm.stopBroadcast();

        console.log("Genesis charger MID: ", chargerMid);
        console.log("Genesis bot MID:     ", botMid);
        console.log("Bot MachineAccount:  ", botAccount);
        console.log("Bot machine key:     ", machineKey);
        console.log("Genesis service id:  ", serviceId);
    }

    function _bindingSig(uint256 pk, uint256 mid, address op, address key) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(REG.KEY_BINDING_TYPEHASH(), mid, op, key));
        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ServoMachineRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(REG)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
