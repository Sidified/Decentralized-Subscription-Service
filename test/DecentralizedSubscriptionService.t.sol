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

    //// TESTS FOR REGITER PLAN /////

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

    //// TESTS FOR DISABLE PLAN /////

    function test_Provider_DisablePlan_RevertsIfInvalidPlanId() external {
        vm.startPrank(alice);

        // planId = 0
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanDoesNotExist.selector);
        dsc.disablePlan(0);

        // planId out of range
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanDoesNotExist.selector);
        dsc.disablePlan(999);

        vm.stopPrank();
    }

    function test_Provider_DisablePlan_RevertsIfNotPlanOwner() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob tries to diable it
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__NotPlanOwner.selector);
        vm.prank(bob);
        dsc.disablePlan(alicePlanId);
    }

    function test_Provider_DisablePlan_RevertsIfPlanAlreadyDisabled() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Alice disabled her plan
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        // Alice trying to disabled her same plan again
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanNotActive.selector);
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);
    }

    function test_Provider_DisablePlan_SetsIsActiveToFalse() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Alice disabled her plan
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        DecentralizedSubscriptionService.Plan memory p = dsc.getPlan(alicePlanId);
        assert(p.isActive == false);
    }

    function test_Provider_DisablePlan_EmitsPlanDisabledEvent() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Alice disabled her plan
        vm.expectEmit(true, false, false, false, address(dsc));
        emit DecentralizedSubscriptionService.PlanDisabled(alicePlanId);
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);
    }

    //// TESTS FOR WITHDRAW PROVIDERS EARNING /////

    function test_Provider_Withdraw_RevertsIfNoEarnings() external {
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__NoEarningsToWithdraw.selector
        );
        vm.prank(alice);
        dsc.withdrawProviderEarnings(address(token));
    }

    function test_Provider_Withdraw_SuccessfulHappyPath() external {
        // Alice registers the plan first
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");
        uint256 planId = dsc.getProviderPlanIds(alice)[0];

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(planId, PRICE_ONE);
        vm.stopPrank();

        uint256 providerEarningBefore = token.balanceOf(alice);
        uint256 contractTokenBalanceBefore = token.balanceOf(address(dsc));

        vm.expectEmit(true, true, false, true, address(dsc));
        emit DecentralizedSubscriptionService.ProviderEarningsWithdrawn(alice, address(token), PRICE_ONE);
        vm.prank(alice);
        dsc.withdrawProviderEarnings(address(token));

        uint256 providerEarningAfter = token.balanceOf(alice);
        uint256 contractTokenBalanceAfter = token.balanceOf(address(dsc));

        assertEq(providerEarningAfter - providerEarningBefore, PRICE_ONE, "Withdrawn amount is not correct");
        assertEq(
            contractTokenBalanceBefore - contractTokenBalanceAfter, PRICE_ONE, "Contract token balace is not correct"
        );
    }

    function test_Provider_Withdraw_ZeroesEarningsAndPreventsDoubleWithdraw() external {
        // Alice registers the plan first
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");
        uint256 planId = dsc.getProviderPlanIds(alice)[0];

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(planId, PRICE_ONE);
        vm.stopPrank();

        // Alice withdraws her earnings
        vm.prank(alice);
        dsc.withdrawProviderEarnings(address(token));

        // Alice withdraws her earnings again
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__NoEarningsToWithdraw.selector
        );
        vm.prank(alice);
        dsc.withdrawProviderEarnings(address(token));
    }

    function test_Provider_Withdraw_OnlyWithdrawsSpecifiedToken() external {
        // Alice registers the plan with token(A)
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "My Plan");
        uint256 planIdA = dsc.getProviderPlanIds(alice)[0];

        MockERC20 tokenB = new MockERC20("Test TokenB", "TSTB");
        // Alice registers the second plan with tokenB
        vm.prank(alice);
        dsc.registerPlan(address(tokenB), PRICE_TWO, INTERVAL_TWO, "My PlanB");
        uint256 planIdB = dsc.getProviderPlanIds(alice)[1];

        // different users subscribe to each
        // Bob subscribes to Alice's plan A
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(planIdA, PRICE_ONE);
        vm.stopPrank();

        // Charlie subscribes to Alice's plan B
        tokenB.mint(charlie, STARTING_TOKEN_BALANCE);
        vm.startPrank(charlie);
        tokenB.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(planIdB, PRICE_TWO);
        vm.stopPrank();

        // Alice withdraws her token(A) earnings
        vm.prank(alice);
        dsc.withdrawProviderEarnings(address(token));

        // assert token A earnings now 0, token B earnings unchanged
        assertEq(dsc.getProviderEarnings(alice, address(token)), 0, "token(A) earnings is not zero");
        assertEq(dsc.getProviderEarnings(alice, address(tokenB)), PRICE_TWO, "tokenB balance is not equals PRICE_TWO ");
    }
}
