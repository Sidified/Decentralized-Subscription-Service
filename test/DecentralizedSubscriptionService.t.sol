// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralizedSubscriptionService} from "src/DecentralizedSubscriptionService.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FeeOnTransferToken} from "./mocks/FeeOnTransferToken.sol";

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

    /////////////////////////////
    //////// USERS TESTS ////////
    /////////////////////////////

    //// TESTS FOR SUBSCRIBE /////
    function test_User_Subscribe_RevertIfPlanIdIsInvalid() external {
        uint256 invalidId = 999;
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanDoesNotExist.selector);
        vm.prank(bob);
        dsc.subscribe(invalidId, PRICE_ONE);
    }

    function test_User_Subscribe_RevertIfPlanIsDisabled() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Alice disabled her plan
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        // Bob tries to subscribe to the diabled plan
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanNotActive.selector);
        vm.prank(bob);
        dsc.subscribe(alicePlanId, PRICE_ONE);
    }

    function test_User_Subscribe_RevertIfAlreadySubscribed() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Bob tries to subscribe again to Alice's plan
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__AlreadySubscribed.selector);
        vm.prank(bob);
        dsc.subscribe(alicePlanId, PRICE_ONE);
    }

    function test_User_Subscribe_RevertIfInsufficientDeposit() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_ONE, "Alice Plan");

        // Bob subscribe to Alice's plan with insufficient amount
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO);
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__InsufficientDeposit.selector);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();
    }

    function test_User_Subscribe_RevertsIfFeeOnTransferDetected() external {
        FeeOnTransferToken fotToken = new FeeOnTransferToken("FoT Token", "FOT");
        // Alice registers a plan with an FOT token
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(fotToken), PRICE_TWO, INTERVAL_ONE, "Alice Plan");

        fotToken.mint(bob, STARTING_TOKEN_BALANCE);
        // Bob tries to subscribe to Alice's plan with FOT token
        vm.startPrank(bob);
        fotToken.approve(address(dsc), PRICE_TWO);
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__FeeOnTransferNotSupported.selector
        );
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();
    }

    function test_User_Subscribe_HappyPath() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 providerEarningBefore = dsc.getProviderEarnings(alice, address(token));
        uint256 contractTokenBalanceBefore = token.balanceOf(address(dsc));
        uint256 nextSubscriptionIdBefore = dsc.getNextSubscriptionId();
        uint256 activeSubscriptionsBefore = dsc.getActiveSubscriptionsCount();

        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO);
        vm.expectEmit(true, true, true, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionCreated(nextSubscriptionIdBefore, bob, alicePlanId, PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        uint256 nextDueDate = block.timestamp + INTERVAL_ONE;
        vm.stopPrank();

        uint256 providerEarningAfter = dsc.getProviderEarnings(alice, address(token));
        uint256 contractTokenBalanceAfter = token.balanceOf(address(dsc));
        uint256 nextSubscriptionIdAfter = dsc.getNextSubscriptionId();
        uint256 activeSubscriptionsAfter = dsc.getActiveSubscriptionsCount();

        uint256 subscriptionId = dsc.getUserSubscriptionId(bob, alicePlanId);
        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(subscriptionId);

        assertEq(s.subscriber, bob, "subscriber not added correctly");
        assertEq(s.planId, alicePlanId, "planId not added correctly");
        assertEq(s.balance, PRICE_TWO - PRICE_ONE, "bob's balance not updated correctly");
        assertEq(s.nextPaymentDue, nextDueDate, "due date not added correctly");
        assert(s.status == DecentralizedSubscriptionService.SubscriptionStatus.Active);
        assertEq(providerEarningAfter - providerEarningBefore, PRICE_ONE, "provider's earnings not updated correctly");
        assertEq(
            contractTokenBalanceAfter - contractTokenBalanceBefore,
            PRICE_TWO,
            "provider's earnings not updated correctly"
        );
        assertEq(nextSubscriptionIdAfter - nextSubscriptionIdBefore, 1, "next subscription ID not updated correctly");
        assertEq(
            activeSubscriptionsAfter - activeSubscriptionsBefore, 1, "active subscription count not updated correctly"
        );
    }

    function test_User_Subscribe_DifferentUserGetsDifferentSubId() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribe to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        assert(bobSubscriptionId == 1);
        assert(charlieSubscriptionId == 2);
    }

    function test_User_Subscribe_SameUserGetsDifferentSubIdForTwoDifferentPlans() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob registers a plan
        uint256 bobPlanId = dsc.getNextPlanId();
        vm.prank(bob);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_TWO, "Bob Plan");

        uint256 charlieSubscriptionIdA = dsc.getNextSubscriptionId();
        // Charlie subscribe to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 charlieSubscriptionIdB = dsc.getNextSubscriptionId();
        // Charlie subscribe to Bob's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(bobPlanId, PRICE_TWO);
        vm.stopPrank();

        assert(charlieSubscriptionIdA == 1);
        assert(charlieSubscriptionIdB == 2);
    }

    function test_User_Subscribe_UserSubscribesThenCancelsThenSubscribesAgain() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Charlie subscribe to Alice's plan
        uint256 charlieSubscriptionIdA = dsc.getNextSubscriptionId();
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Charlie cancels the plan
        vm.prank(charlie);
        dsc.cancelSubscription(charlieSubscriptionIdA);

        // Charlie subscribes again
        uint256 charlieSubscriptionIdB = dsc.getNextSubscriptionId();
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        assert(charlieSubscriptionIdA == 1);
        assert(charlieSubscriptionIdB == 2);
    }
}
