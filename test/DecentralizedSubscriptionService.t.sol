// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralizedSubscriptionService} from "src/DecentralizedSubscriptionService.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract DecentralizedSubscriptionServiceTest is Test {
    //// CONTRACT UNDER TEST ////
    DecentralizedSubscriptionService dsc;

    //// MOCKS ////
    MockERC20 token;

    //// TEST ACTORS ////
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    //// CONSTANTS ////
    uint256 constant STARTING_TOKEN_BALANCE = 1_000_000 ether;
    uint256 constant INTERVAL_ONE = 7 days;
    uint256 constant INTERVAL_TWO = 10 days;
    uint256 constant PRICE_ONE = 5 ether;
    uint256 constant PRICE_TWO = 10 ether;

    function setUp() external {
        // Deploy contract under test
        dsc = new DecentralizedSubscriptionService();

        // Deploy mock ERC20
        token = new MockERC20("Test Token", "TST");

        // Mint tokens to test actors
        token.mint(alice, STARTING_TOKEN_BALANCE);
        token.mint(bob, STARTING_TOKEN_BALANCE);
        token.mint(charlie, STARTING_TOKEN_BALANCE);
    }

    /////////////////////////////
    ////// PROVIDERS TESTS //////
    /////////////////////////////

    //// TESTS FOR REGITER PLAN ///// RegisterPlan_

    function test_Provider_RegisterPlan_RevertsIfInvalidToken() external {
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__InvalidTokenAddress.selector);
        vm.prank(alice);
        dsc.registerPlan(address(0), PRICE_ONE, INTERVAL_ONE, "MY Plan");
    }

    function test_Provider_RegisterPlan_RevertsIfPriceIsZero() external {
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanPriceMustBeNonZero.selector
        );
        vm.prank(alice);
        dsc.registerPlan(address(token), 0, INTERVAL_ONE, "My Plan");
    }

    function test_Provider_RegisterPlan_RevertsIfIntervalIsZero() external {
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanIntervalMustBeNonZero.selector
        );
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, 0, "My Plan");
    }

    function test_Provider_RegisterPlan_AllSixFieldsAreSetCorrectly() external {
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");

        // Fetch the planId and struct
        uint256[] memory planIdArray = dsc.getProviderPlanIds(alice);
        uint256 planId = planIdArray[0];
        DecentralizedSubscriptionService.Plan memory p = dsc.getPlan(planId);

        assertEq(p.provider, alice, "Provider mismatch");
        assertEq(p.token, address(token), "Token mismatch");
        assertEq(p.price, PRICE_ONE, "Price Mismatch");
        assertEq(p.interval, INTERVAL_ONE, "Interval Mismatch");
        assertEq(p.isActive, true, "isActive should be true");
        assertEq(p.name, "My Plan");
    }

    function test_Provider_RegisterPlan_IncrementsPlanIdCounter() external {
        uint256 planIdBefore = dsc.getNextPlanId();

        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");

        uint256 planIdAfter = dsc.getNextPlanId();

        assertEq(planIdAfter - planIdBefore, 1, "Increment mismatch");
    }

    function test_Provider_RegisterPlan_EmitsPlanRegisteredEvents() external {
        // Dynamically read what the ID will be
        uint256 expectedPlanId = dsc.getNextPlanId();

        vm.expectEmit(true, true, true, true, address(dsc));
        emit DecentralizedSubscriptionService.PlanRegistered(
            expectedPlanId, alice, address(token), PRICE_ONE, INTERVAL_ONE, "My Plan"
        );
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");
    }

    function test_Provider_RegisterPlan_AppendsToProviderPlanIds() external {
        // Alice registers two plans
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");

        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_TWO, "My Second Plan");

        // Fetch the planId and struct
        uint256[] memory planIdArray = dsc.getProviderPlanIds(alice);
        uint256 planIdOne = planIdArray[0];
        uint256 planIdTwo = planIdArray[1];

        assert(dsc.getProviderPlanIds(alice).length == 2);
        assert(planIdOne == 1);
        assert(planIdTwo == 2);
    }

    function test_Provider_GetProviderPlanIds_ReturnsEmptyForNonProvider() external view {
        // Bob never registered
        assert(dsc.getProviderPlanIds(bob).length == 0);
    }

    function test_Provider_RegisterPlan_DifferentProvidersHaveIndependentPlanLists() external {
        // Alice registers a plan and then Bob registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");
        assert(dsc.getProviderPlanIds(alice).length == 1);
        assert(alicePlanId == 1);

        uint256 bobPlanId = dsc.getNextPlanId();
        vm.prank(bob);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_TWO, "Bob Plan");
        assert(dsc.getProviderPlanIds(alice).length == 1);
        assert(bobPlanId == 2);
    }
}
