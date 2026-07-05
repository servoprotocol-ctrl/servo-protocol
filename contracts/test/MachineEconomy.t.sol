// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {MachineAccount} from "../src/MachineAccount.sol";
import {MachineAccountFactory} from "../src/MachineAccountFactory.sol";
import {FleetVault} from "../src/FleetVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @notice End-to-end tests of the Servo machine economy: a delivery robot with a
///         funded MachineAccount buys charging from a provider whose revenue routes
///         into a FleetVault and distributes to beneficiaries.
contract MachineEconomyTest is Test {
    MachineRegistry registry;
    ServiceRegistry services;
    MachineAccountFactory factory;
    MockUSDC usdc;

    address gov = makeAddr("gov");
    address treasury = makeAddr("treasury");
    address operator = makeAddr("operator"); // operates the delivery robot
    address chargeCo = makeAddr("chargeCo"); // operates the charging network
    address financier = makeAddr("financier");

    uint256 botPk;
    address botKey;
    uint256 botMid;
    MachineAccount botAccount;

    uint256 chargerMid;
    FleetVault chargerVault;
    uint256 serviceId;

    uint96 constant CHARGE_PRICE = 5e6; // 5 USDC per session
    bytes32 constant CATEGORY_CHARGING = keccak256("CHARGING");

    function setUp() public {
        registry = new MachineRegistry(gov);
        services = new ServiceRegistry(registry, gov, treasury);
        factory = new MachineAccountFactory(registry, services);
        usdc = new MockUSDC();

        // ServiceRegistry is the authorized commerce recorder (as in deployment).
        vm.prank(gov);
        registry.setRecorder(address(services), true);

        (botKey, botPk) = makeAddrAndKey("botKey");

        // --- delivery robot: identity + bound key + funded account
        vm.startPrank(operator);
        botMid = registry.registerMachine(
            operator, keccak256("bot-hw"), MachineRegistry.MachineClass.MobileGround, "ipfs://bot"
        );
        registry.bindMachineKey(botMid, botKey, _bindingSig(botMid, operator, botPk, botKey));
        botAccount = MachineAccount(payable(factory.createAccount(botMid)));
        botAccount.setDailyCap(address(usdc), 20e6); // 20 USDC/day
        vm.stopPrank();
        usdc.mint(address(botAccount), 100e6);

        // --- charging provider: machine identity + fleet vault + service listing
        vm.startPrank(chargeCo);
        chargerMid = registry.registerMachine(
            chargeCo, keccak256("charger-hw"), MachineRegistry.MachineClass.Stationary, "ipfs://charger"
        );
        FleetVault.Beneficiary[] memory splits = new FleetVault.Beneficiary[](2);
        splits[0] = FleetVault.Beneficiary({account: chargeCo, bps: 7000});
        splits[1] = FleetVault.Beneficiary({account: financier, bps: 3000});
        chargerVault = new FleetVault(registry, usdc, chargeCo, splits);
        chargerVault.addMachine(chargerMid);
        serviceId = services.registerService(
            chargerMid, address(chargerVault), address(usdc), CHARGE_PRICE, CATEGORY_CHARGING, true,
            "https://charge.example/x402"
        );
        vm.stopPrank();
    }

    // ------------------------------------------------------------- helpers

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

    // ----------------------------------------------------- end-to-end flow

    function test_e2e_robotBuysCharging_revenueFlowsToVaultAndDistributes() public {
        // Robot autonomously buys a charging session.
        vm.prank(botKey);
        botAccount.purchase(serviceId);

        // Payment left the robot's account: price 5 USDC, 1% protocol fee.
        assertEq(usdc.balanceOf(address(botAccount)), 95e6);
        assertEq(usdc.balanceOf(address(chargerVault)), 4.95e6);
        assertEq(usdc.balanceOf(treasury), 0.05e6);

        // Receipt updated the service's commerce stats.
        ServiceRegistry.Service memory s = services.getService(serviceId);
        assertEq(s.unitsSold, 1);
        assertEq(s.grossRevenue, CHARGE_PRICE);

        // Vault settlement attributed the sale to the charger's onchain P&L.
        assertEq(chargerVault.machineRevenue(chargerMid), 4.95e6);
        assertEq(chargerVault.totalRevenue(), 4.95e6);

        // The provable service record was written from the real settlement:
        // net revenue (price minus fee) and one completed job.
        MachineRegistry.Machine memory cm = registry.getMachine(chargerMid);
        assertEq(cm.revenueAttested, 4.95e6);
        assertEq(cm.jobsAttested, 1);

        // Beneficiaries can claim their splits of the settled revenue: 70/30.
        vm.prank(chargeCo);
        chargerVault.claim();
        vm.prank(financier);
        chargerVault.claim();
        assertEq(usdc.balanceOf(chargeCo), 3.465e6);
        assertEq(usdc.balanceOf(financier), 1.485e6);
    }

    function test_e2e_attributedDeposit_thenClaims() public {
        // A gateway (any payer) attributes 10 USDC of revenue to the charger.
        address gateway = makeAddr("gateway");
        usdc.mint(gateway, 10e6);
        vm.startPrank(gateway);
        usdc.approve(address(chargerVault), 10e6);
        chargerVault.deposit(chargerMid, 10e6);
        vm.stopPrank();

        assertEq(chargerVault.machineRevenue(chargerMid), 10e6);
        assertEq(chargerVault.totalRevenue(), 10e6);

        // Beneficiaries claim their splits: 70/30.
        vm.prank(chargeCo);
        chargerVault.claim();
        vm.prank(financier);
        chargerVault.claim();

        assertEq(usdc.balanceOf(chargeCo), 7e6);
        assertEq(usdc.balanceOf(financier), 3e6);
    }

    // ------------------------------------------------------ policy envelope

    function test_policy_dailyCapEnforced() public {
        // Cap is 20 USDC/day; each session is 5 USDC. Four succeed, fifth fails.
        vm.startPrank(botKey);
        for (uint256 i = 0; i < 4; i++) {
            botAccount.purchase(serviceId);
        }
        vm.expectRevert(
            abi.encodeWithSelector(MachineAccount.DailyCapExceeded.selector, address(usdc), CHARGE_PRICE, 0)
        );
        botAccount.purchase(serviceId);
        vm.stopPrank();

        // Next day the envelope resets.
        vm.warp(block.timestamp + 1 days);
        vm.prank(botKey);
        botAccount.purchase(serviceId);
        assertEq(usdc.balanceOf(address(botAccount)), 75e6);
    }

    function test_policy_allowlistBlocksUnknownCounterparty() public {
        vm.startPrank(operator);
        botAccount.setAllowlistEnabled(true);
        vm.stopPrank();

        vm.prank(botKey);
        vm.expectRevert(
            abi.encodeWithSelector(MachineAccount.CounterpartyNotAllowed.selector, address(chargerVault))
        );
        botAccount.purchase(serviceId);

        // Operator allowlists the charging vault; purchase now succeeds.
        vm.prank(operator);
        botAccount.setCounterparty(address(chargerVault), true);
        vm.prank(botKey);
        botAccount.purchase(serviceId);
    }

    function test_policy_pauseIsKillSwitch() public {
        vm.prank(operator);
        botAccount.setPaused(true);

        vm.prank(botKey);
        vm.expectRevert(MachineAccount.AccountIsPaused.selector);
        botAccount.pay(address(usdc), makeAddr("anyone"), 1e6, "memo");
    }

    function test_policy_registryPauseBlocksSpending() public {
        vm.prank(operator);
        registry.pauseMachine(botMid);

        vm.prank(botKey);
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.MachineNotActive.selector, botMid));
        botAccount.purchase(serviceId);
    }

    function test_policy_tokenWithoutCapNotSpendable() public {
        MockUSDC other = new MockUSDC();
        other.mint(address(botAccount), 10e6);

        vm.prank(botKey);
        vm.expectRevert(abi.encodeWithSelector(MachineAccount.TokenNotSpendable.selector, address(other)));
        botAccount.pay(address(other), makeAddr("anyone"), 1e6, "memo");
    }

    function test_onlyMachineKeyCanSpend() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(MachineAccount.NotMachineKey.selector);
        botAccount.pay(address(usdc), makeAddr("anyone"), 1e6, "memo");

        // The operator also cannot use the machine-key path; it uses execute().
        vm.prank(operator);
        vm.expectRevert(MachineAccount.NotMachineKey.selector);
        botAccount.pay(address(usdc), makeAddr("anyone"), 1e6, "memo");
    }

    function test_operatorExecute_withdrawsFunds() public {
        vm.prank(operator);
        botAccount.execute(
            address(usdc), 0, abi.encodeWithSelector(usdc.transfer.selector, operator, 50e6)
        );
        assertEq(usdc.balanceOf(operator), 50e6);
    }

    function test_operatorExecute_onlyOperator() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(MachineAccount.NotOperator.selector);
        botAccount.execute(address(usdc), 0, "");
    }

    // ---------------------------------------------------------- marketplace

    function test_service_externalReceipt_onlyFacilitator() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(abi.encodeWithSelector(ServiceRegistry.NotFacilitator.selector, makeAddr("rando")));
        services.recordExternalReceipt(serviceId, botMid, 5e6);

        vm.prank(gov);
        services.setFacilitator(makeAddr("x402gateway"), true);

        vm.prank(makeAddr("x402gateway"));
        services.recordExternalReceipt(serviceId, botMid, 5e6);

        ServiceRegistry.Service memory s = services.getService(serviceId);
        assertEq(s.unitsSold, 1);
        assertEq(s.grossRevenue, 5e6);
    }

    function test_service_pausedProviderMachineBlocksPurchase() public {
        vm.prank(chargeCo);
        registry.pauseMachine(chargerMid);

        vm.prank(botKey);
        vm.expectRevert(abi.encodeWithSelector(MachineRegistry.MachineNotActive.selector, chargerMid));
        botAccount.purchase(serviceId);
    }

    function test_service_updateAndDeactivate() public {
        vm.prank(chargeCo);
        services.updateService(serviceId, address(chargerVault), 6e6, false, "https://charge.example/x402");

        vm.prank(botKey);
        vm.expectRevert(abi.encodeWithSelector(ServiceRegistry.ServiceNotActive.selector, serviceId));
        botAccount.purchase(serviceId);
    }

    function test_service_feeCap() public {
        vm.prank(gov);
        vm.expectRevert(abi.encodeWithSelector(ServiceRegistry.FeeTooHigh.selector, uint16(501)));
        services.setProtocolFee(501, treasury);
    }

    // ---------------------------------------------------------------- vault

    function test_vault_cannotAttributeToForeignMachine() public {
        // botMid is not enrolled in chargerVault's fleet.
        usdc.mint(address(this), 1e6);
        usdc.approve(address(chargerVault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(FleetVault.NotFleetMachine.selector, botMid));
        chargerVault.deposit(botMid, 1e6);
    }

    function test_vault_addMachine_requiresRegistryOwnership() public {
        // chargeCo cannot enroll the bot it does not operate.
        vm.prank(chargeCo);
        vm.expectRevert(abi.encodeWithSelector(FleetVault.NotMachineOperator.selector, botMid));
        chargerVault.addMachine(botMid);
    }

    function test_vault_badSplitsRevert() public {
        FleetVault.Beneficiary[] memory bad = new FleetVault.Beneficiary[](1);
        bad[0] = FleetVault.Beneficiary({account: chargeCo, bps: 9999});
        vm.expectRevert(FleetVault.BadSplits.selector);
        new FleetVault(registry, usdc, chargeCo, bad);
    }

    function test_factory_oneAccountPerMachine() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(MachineAccountFactory.AccountExists.selector, botMid));
        factory.createAccount(botMid);
    }

    function test_factory_onlyOperatorCreates() public {
        // chargeCo is not the bot's operator.
        vm.prank(chargeCo);
        vm.expectRevert(abi.encodeWithSelector(MachineAccountFactory.NotOperator.selector, botMid));
        factory.createAccount(botMid);
    }
}
