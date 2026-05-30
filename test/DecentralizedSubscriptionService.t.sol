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

    //// TESTS FOR TOPUP /////

    function test_User_TopUp_RevertsIfInvalidSubscriptionId() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 randomSubId = 999;

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionDoesNotExist.selector
        );
        vm.prank(bob);
        dsc.topUp(randomSubId, PRICE_TWO);
    }

    function test_User_TopUp_RevertsIfNotOwner() external {
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

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__NotSubscriptionOwner.selector
        );
        vm.prank(charlie);
        dsc.topUp(bobSubscriptionId, PRICE_TWO);
    }

    function test_User_TopUp_RevertsIfSubscriptionNotActive() external {
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

        // Bob cancels his subscription
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);

        vm.prank(bob);
        token.approve(address(dsc), PRICE_TWO);

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionNotActive.selector
        );
        vm.prank(bob);
        dsc.topUp(bobSubscriptionId, PRICE_TWO);
    }

    function test_User_TopUp_RevertsIfTopUpAmountIsZero() external {
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

        vm.prank(bob);
        token.approve(address(dsc), PRICE_TWO);

        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__AmountMustBeNonZero.selector);
        vm.prank(bob);
        dsc.topUp(bobSubscriptionId, 0);
    }

    function test_User_TopUp_HappyPath() external {
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

        vm.prank(bob);
        token.approve(address(dsc), PRICE_TWO);

        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceBefore = s.balance;
        uint256 tokenBalanceOfContractBefore = token.balanceOf(address(dsc));

        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionToppedUp(bobSubscriptionId, PRICE_TWO, s.balance + PRICE_TWO);
        vm.prank(bob);
        dsc.topUp(bobSubscriptionId, PRICE_TWO);

        DecentralizedSubscriptionService.Subscription memory ss = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceAfter = ss.balance;
        uint256 tokenBalanceOfContractAfter = token.balanceOf(address(dsc));

        assertEq(balanceAfter - balanceBefore, PRICE_TWO, "balance did not updated correctly");
        assertEq(
            tokenBalanceOfContractAfter - tokenBalanceOfContractBefore,
            PRICE_TWO,
            "token balace of contract did not updated correctly"
        );
    }

    function test_User_TopUp_TopUPActiveSubscriptionMultipleTimes() external {
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

        vm.prank(bob);
        token.approve(address(dsc), PRICE_TWO);

        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceBefore = s.balance;
        uint256 tokenBalanceOfContractBefore = token.balanceOf(address(dsc));

        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionToppedUp(bobSubscriptionId, PRICE_TWO, s.balance + PRICE_TWO);
        vm.prank(bob);
        dsc.topUp(bobSubscriptionId, PRICE_TWO);

        DecentralizedSubscriptionService.Subscription memory ss = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceAfter = ss.balance;
        uint256 tokenBalanceOfContractAfter = token.balanceOf(address(dsc));

        assertEq(balanceAfter - balanceBefore, PRICE_TWO, "balance did not updated correctly");
        assertEq(
            tokenBalanceOfContractAfter - tokenBalanceOfContractBefore,
            PRICE_TWO,
            "token balace of contract did not updated correctly"
        );

        vm.prank(bob);
        token.approve(address(dsc), PRICE_ONE);

        DecentralizedSubscriptionService.Subscription memory a = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceBeforeA = a.balance;
        uint256 tokenBalanceOfContractBeforeA = token.balanceOf(address(dsc));

        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionToppedUp(bobSubscriptionId, PRICE_ONE, a.balance + PRICE_ONE);
        vm.prank(bob);
        dsc.topUp(bobSubscriptionId, PRICE_ONE);

        DecentralizedSubscriptionService.Subscription memory aa = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceAfterA = aa.balance;
        uint256 tokenBalanceOfContractAfterA = token.balanceOf(address(dsc));

        assertEq(balanceAfterA - balanceBeforeA, PRICE_ONE, "balance did not updated correctly");
        assertEq(
            tokenBalanceOfContractAfterA - tokenBalanceOfContractBeforeA,
            PRICE_ONE,
            "token balace of contract did not updated correctly"
        );
    }

    function test_User_TopUp_RevertsIfSubscriptionLapsed() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        // Bob subscribes with exactly PRICE_ONE, leaving a balance of 0
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // --- LAPSE THE SUBSCRIPTION ---
        // Fast forward past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Execute upkeep to kick Bob into Lapsed status
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // --- ATTEMPT TOP UP (SHOULD REVERT) ---
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionNotActive.selector
        );
        dsc.topUp(bobSubscriptionId, PRICE_ONE);
        vm.stopPrank();
    }

    function test_User_TopUp_WorksOnActiveSubscriptionOfDisabledPlan() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // --- DISABLE PLAN ---
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        // Quick sanity check to ensure the plan is actually disabled
        assertFalse(dsc.getPlan(alicePlanId).isActive, "Plan failed to disable");

        // --- TOP UP (THE CORE TEST) ---
        uint256 topUpAmount = PRICE_ONE;
        uint256 balanceBefore = dsc.getSubscription(bobSubscriptionId).balance;

        vm.startPrank(bob);
        token.approve(address(dsc), topUpAmount);

        // This should succeed silently without reverting
        dsc.topUp(bobSubscriptionId, topUpAmount);
        vm.stopPrank();

        // --- ASSERTION ---
        assertEq(
            dsc.getSubscription(bobSubscriptionId).balance,
            balanceBefore + topUpAmount,
            "Top-up failed on disabled plan"
        );
    }

    //// TESTS FOR CANCEL SUBSCRIPTION /////

    // TODO: Write test_User_CancelSub_HappyPathOnLapsedSubscription
    // (Defer until performUpkeep test machinery exists so we can easily generate a Lapsed state)

    function test_User_CancelSub_RevertIfInvalidSubId() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 randomSubId = 999;
        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionDoesNotExist.selector
        );
        vm.prank(bob);
        dsc.cancelSubscription(randomSubId);
    }

    function test_User_CancelSub_RevertIfNotOwner() external {
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

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__NotSubscriptionOwner.selector
        );
        vm.prank(charlie);
        dsc.cancelSubscription(bobSubscriptionId);
    }

    function test_User_CancelSub_RevertIfAlreadyCancelled() external {
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

        // Cancel the subscription
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);

        // Try to cancel the subscription again
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionAlreadyCancelled.selector
        );
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);
    }

    function test_User_CancelSub_HappyPath() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribe to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Pre-cancel state captures
        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);
        uint256 balance = s.balance;
        uint256 activeSubCountBefore = dsc.getActiveSubscriptionsCount();

        uint256 bobTokenBefore = token.balanceOf(bob);
        uint256 contractTokenBefore = token.balanceOf(address(dsc));
        uint256 providerEarningsBefore = dsc.getProviderEarnings(alice, address(token));

        // Cancel the subscription
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionCancelled(bobSubscriptionId, balance);
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);

        // Post-cancel state captures
        DecentralizedSubscriptionService.Subscription memory sA = dsc.getSubscription(bobSubscriptionId);
        uint256 balanceA = sA.balance;
        uint256 activeSubCountAfter = dsc.getActiveSubscriptionsCount();

        // Internal State Assertions
        assertTrue(
            sA.status == DecentralizedSubscriptionService.SubscriptionStatus.Cancelled,
            "Status did not change to Cancelled"
        );
        assertEq(dsc.getUserSubscriptionId(bob, alicePlanId), 0, "subscription not removed"); // Updated duplicate function name here
        assert(balanceA == 0);
        assertEq(activeSubCountBefore - activeSubCountAfter, 1, "active subscription count not changed");

        // Token Movement & Earnings Assertions
        assertEq(token.balanceOf(bob), bobTokenBefore + balance, "Bob did not receive refund");
        assertEq(token.balanceOf(address(dsc)), contractTokenBefore - balance, "Contract balance did not decrease");
        assertEq(
            dsc.getProviderEarnings(alice, address(token)),
            providerEarningsBefore,
            "Provider earnings should not change on cancel"
        );
    }

    function test_User_CancelSub_HappyPathWithZeroBalace() external {
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

        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);
        uint256 balance = s.balance;

        // Cancel the subscription
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionCancelled(bobSubscriptionId, balance);
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);

        assert(balance == 0);
    }

    function test_User_CancelSub_SwapAndPopIntegrity() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Give them all allowance
        vm.prank(alice);
        token.approve(address(dsc), PRICE_ONE);
        vm.prank(bob);
        token.approve(address(dsc), PRICE_ONE);
        vm.prank(charlie);
        token.approve(address(dsc), PRICE_ONE);

        // Array should look like: [sub1, sub2, sub3]

        vm.prank(alice);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        uint256 sub1 = dsc.getUserSubscriptionId(alice, alicePlanId); // Index 0

        vm.prank(bob);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        uint256 sub2 = dsc.getUserSubscriptionId(bob, alicePlanId); // Index 1 (The Middle)

        vm.prank(charlie);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        uint256 sub3 = dsc.getUserSubscriptionId(charlie, alicePlanId); // Index 2 (The Last)

        // Sanity check before cancellation
        assertEq(dsc.getActiveSubscriptionsCount(), 3, "Should have 3 active subs");
        assertEq(dsc.getActiveSubscriptionIdAtIndex(1), sub2, "Bob should be in the middle");

        // Cancel the middle subscription (Bob's)
        vm.prank(bob);
        dsc.cancelSubscription(sub2);

        // The Swap and Pop
        // Expected Array: [sub1, sub3]

        // Check 1: The length shrank by exactly 1
        assertEq(dsc.getActiveSubscriptionsCount(), 2, "Length did not shrink correctly");

        // Check 2: The first item (Alice) was completely untouched
        assertEq(dsc.getActiveSubscriptionIdAtIndex(0), sub1, "Index 0 was corrupted");

        // Check 3: The crucial swap.
        // Charlie (sub3) should have been moved from the end (Index 2) into Bob's old spot (Index 1)
        assertEq(dsc.getActiveSubscriptionIdAtIndex(1), sub3, "Swap-and-pop failed to move the last item");
    }

    function test_User_CancelSub_HappyPathOnLapsedSubscription() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes with PRICE_TWO + PRICE_ONE.
        // Contract takes PRICE_TWO. Bob has PRICE_ONE left in his balance.
        uint256 depositAmount = PRICE_TWO + PRICE_ONE;
        vm.startPrank(bob);
        token.approve(address(dsc), depositAmount);
        dsc.subscribe(alicePlanId, depositAmount);
        vm.stopPrank();

        // --- LAPSE THE SUBSCRIPTION ---
        // Fast forward past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Upkeep runs. Bob owes PRICE_TWO, but only has PRICE_ONE. He lapses.
        // The upkeep removes him from the active array here.
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // --- PRE-CANCEL CAPTURE ---
        uint256 bobTokenBefore = token.balanceOf(bob);
        uint256 contractTokenBefore = token.balanceOf(address(dsc));
        uint256 activeArrayCountBeforeCancel = dsc.getActiveSubscriptionsCount();

        // --- CANCEL ---
        vm.prank(bob);
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionCancelled(bobSubscriptionId, PRICE_ONE);
        dsc.cancelSubscription(bobSubscriptionId);

        // --- POST-CANCEL ASSERTIONS ---
        DecentralizedSubscriptionService.Subscription memory cancelledSub = dsc.getSubscription(bobSubscriptionId);

        // 1. Status updated to Cancelled and balance zeroed
        assertTrue(
            cancelledSub.status == DecentralizedSubscriptionService.SubscriptionStatus.Cancelled,
            "Status not updated to Cancelled"
        );
        assertEq(cancelledSub.balance, 0, "Balance not zeroed out");

        // 2. Active array count UNCHANGED
        // (Because it was already removed during Upkeep, the cancel function should have skipped array removal)
        assertEq(
            dsc.getActiveSubscriptionsCount(),
            activeArrayCountBeforeCancel,
            "Array count changed! Contract tried to double-remove a lapsed sub."
        );

        // 3. Tokens successfully refunded (He got his leftover PRICE_ONE back)
        assertEq(token.balanceOf(bob), bobTokenBefore + PRICE_ONE, "Bob did not receive his refund");
        assertEq(token.balanceOf(address(dsc)), contractTokenBefore - PRICE_ONE, "Contract balance did not decrease");

        // 4. Mapping correctly cleared
        assertEq(dsc.getUserSubscriptionId(bob, alicePlanId), 0, "User to Sub mapping not cleared");
    }

    //// TESTS FOR REACTIVATE SUBSCRIPTION /////

    function test_User_Reactivate_RevertIfInvalidSubId() external {
        // Alice registers a plan
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 randomSubId = 999;
        uint256 depositAmount = PRICE_ONE;

        // Try to reactivate a subscription that doesn't exist
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionDoesNotExist.selector
        );
        vm.prank(bob);
        dsc.reactivate(randomSubId, depositAmount);
    }

    function test_User_Reactivate_RevertIfNotOwner() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 depositAmount = PRICE_ONE;

        // Charlie tries to hijack Bob's subscription
        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__NotSubscriptionOwner.selector
        );
        vm.prank(charlie);
        dsc.reactivate(bobSubscriptionId, depositAmount);
    }

    function test_User_Reactivate_RevertIfNotLapsed() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // At this point, the subscription status is Active.
        // It must be Lapsed to be reactivated.
        uint256 depositAmount = PRICE_ONE;

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionNotLapsed.selector
        );
        vm.prank(bob);
        dsc.reactivate(bobSubscriptionId, depositAmount);
    }

    function test_User_Reactivate_HappyPath() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Fast forward the time past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Perform the upkeep
        // Bob's balance is now less than the Plan Price so his subscription will be lapsed
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // --- PRE-REACTIVATE STATE CAPTURE ---
        uint256 providerEarningsBefore = dsc.getProviderEarnings(alice, address(token));
        uint256 contractTokenBefore = token.balanceOf(address(dsc));
        uint256 bobTokenBefore = token.balanceOf(bob);
        uint256 activeArrayCountBefore = dsc.getActiveSubscriptionsCount();

        // Now Bob's subscription is in lapsed status.
        // Bob reactivates the subscription.
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);

        // 1. ASSERT EVENT
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionReactivated(bobSubscriptionId, PRICE_ONE);
        dsc.reactivate(bobSubscriptionId, PRICE_ONE);
        vm.stopPrank();

        // POST-REACTIVATE STATE CAPTURE
        DecentralizedSubscriptionService.Subscription memory sAfter = dsc.getSubscription(bobSubscriptionId);
        uint256 activeArrayCountAfter = dsc.getActiveSubscriptionsCount();

        // INTERNAL LOGIC ASSERTIONS
        // 2. Status flips to Active
        assertTrue(
            sAfter.status == DecentralizedSubscriptionService.SubscriptionStatus.Active,
            "Status did not change to Active"
        );

        // 3. Balance carries forward (0 previous + PRICE_ONE deposit - PRICE_ONE price = 0)
        assertEq(sAfter.balance, 0, "Balance carry-forward math incorrect");

        // 4. nextPaymentDue resets
        assertEq(sAfter.nextPaymentDue, block.timestamp + INTERVAL_ONE, "Due date not reset");

        // 5. Added back to active array (Count increases, and it is pushed to the very end)
        assertEq(activeArrayCountAfter - activeArrayCountBefore, 1, "Not added back to active array");
        assertEq(
            dsc.getActiveSubscriptionIdAtIndex(activeArrayCountAfter - 1),
            bobSubscriptionId,
            "Wrong ID pushed to active array"
        );

        // ACCOUNTING ASSERTIONS
        // 6. Provider earnings credited
        assertEq(
            dsc.getProviderEarnings(alice, address(token)) - providerEarningsBefore,
            PRICE_ONE,
            "Provider earnings not credited"
        );

        // 7. Token transfers actually happened
        assertEq(bobTokenBefore - token.balanceOf(bob), PRICE_ONE, "Tokens not pulled from Bob");
        assertEq(token.balanceOf(address(dsc)) - contractTokenBefore, PRICE_ONE, "Tokens not sent to contract");
    }

    function test_User_Reactivate_PlanDisablesAfterTheSubscriptionLapsed() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Fast forward the time past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Perform the upkeep
        // Bob's balance is now less than the Plan Price so his subscription will be lapsed
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // Now the Bob's subscription will be in lapse status

        // Alice disabled her before plan
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        // Bob try to reactivates the subscription.
        // This will revert
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanNotActive.selector);
        dsc.reactivate(bobSubscriptionId, PRICE_ONE);
        vm.stopPrank();
    }

    function test_User_Reactivate_BoundaryMath_ExactBalance() external {
        // SETUP
        // 1. Alice creates a plan for 10 Tokens
        uint256 planPrice = 10e18; // Using realistic ERC20 decimals
        uint256 alicePlanId = dsc.getNextPlanId();

        vm.prank(alice);
        dsc.registerPlan(address(token), planPrice, INTERVAL_ONE, "Alice Boundary Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // 2. Bob subscribes and intentionally deposits 13 Tokens (overpaying by 3)
        uint256 overpayment = 3e18;
        uint256 initialDeposit = planPrice + overpayment; // 13 Tokens

        vm.startPrank(bob);
        token.approve(address(dsc), initialDeposit);
        dsc.subscribe(alicePlanId, initialDeposit);
        vm.stopPrank();

        // Verify Bob has a leftover balance of 3 Tokens
        assertEq(dsc.getSubscription(bobSubscriptionId).balance, overpayment, "Initial overpayment not recorded");

        // LAPSE THE SUBSCRIPTION
        // Fast forward the time past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Perform the upkeep.
        // Bob owes 10 tokens, but only has 3. He lapses.
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        assertTrue(
            dsc.getSubscription(bobSubscriptionId).status == DecentralizedSubscriptionService.SubscriptionStatus.Lapsed,
            "Subscription did not lapse"
        );

        // REACTIVATE (THE BOUNDARY TEST)
        // Bob needs 10 tokens total to reactivate.
        // He already has 3 tokens sitting in his balance.
        // He should only need to deposit exactly 7 tokens.
        uint256 exactReactivationDeposit = planPrice - overpayment; // 7 Tokens

        vm.startPrank(bob);
        token.approve(address(dsc), exactReactivationDeposit);

        // This transaction should succeed (not revert!)
        dsc.reactivate(bobSubscriptionId, exactReactivationDeposit);
        vm.stopPrank();

        // VERIFY BOUNDARY MATH
        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);

        // His balance should be perfectly drained to zero
        assertEq(s.balance, 0, "Boundary math failed to resolve to exactly zero");

        // His status should be active again
        assertTrue(
            s.status == DecentralizedSubscriptionService.SubscriptionStatus.Active,
            "Failed to reactivate on exact boundary math"
        );
    }

    function test_User_Reactivate_CarryForwardWithRemainder() external {
        // SETUP
        uint256 planPrice = 4e18; // Price = 4
        uint256 alicePlanId = dsc.getNextPlanId();

        vm.prank(alice);
        dsc.registerPlan(address(token), planPrice, INTERVAL_ONE, "Alice Remainder Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes and intentionally deposits 6 Tokens.
        // Contract takes 4 for the first month.
        // Bob's starting balance is exactly 2.
        uint256 initialDeposit = 6e18;

        vm.startPrank(bob);
        token.approve(address(dsc), initialDeposit);
        dsc.subscribe(alicePlanId, initialDeposit);
        vm.stopPrank();

        assertEq(dsc.getSubscription(bobSubscriptionId).balance, 2e18, "Initial balance should be 2");

        // LAPSE THE SUBSCRIPTION
        // Fast forward the time past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Perform the upkeep.
        // Bob owes 4 tokens, but only has 2. He lapses.
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // REACTIVATE (THE REMAINDER TEST)
        // Bob deposits 3 tokens.
        // Existing Balance (2) + Deposit (3) = 5 Tokens total.
        // Plan Price is 4.
        uint256 reactivateDeposit = 3e18;

        vm.startPrank(bob);
        token.approve(address(dsc), reactivateDeposit);

        // This should succeed because 5 >= 4
        dsc.reactivate(bobSubscriptionId, reactivateDeposit);
        vm.stopPrank();

        // VERIFY ARITHMETIC
        DecentralizedSubscriptionService.Subscription memory s = dsc.getSubscription(bobSubscriptionId);

        // His balance should be 5 - 4 = 1
        assertEq(s.balance, 1e18, "Carry-forward math failed to leave a remainder of 1");

        // His status should be active again
        assertTrue(
            s.status == DecentralizedSubscriptionService.SubscriptionStatus.Active,
            "Failed to reactivate with carry-forward remainder"
        );
    }

    function test_User_Reactivate_RevertIfInsufficientCombinedDeposit() external {
        // SETUP
        uint256 planPrice = 4e18; // Price = 4
        uint256 alicePlanId = dsc.getNextPlanId();

        vm.prank(alice);
        dsc.registerPlan(address(token), planPrice, INTERVAL_ONE, "Alice Insufficient Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes and intentionally deposits 6 Tokens.
        // Contract takes 4 for the first month.
        // Bob's starting balance is exactly 2.
        uint256 initialDeposit = 6e18;

        vm.startPrank(bob);
        token.approve(address(dsc), initialDeposit);
        dsc.subscribe(alicePlanId, initialDeposit);
        vm.stopPrank();

        // LAPSE THE SUBSCRIPTION
        // Fast forward the time past the interval
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Perform the upkeep.
        // Bob owes 4 tokens, but only has 2. He lapses.
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // REACTIVATE (THE REVERT TEST)
        // Bob attempts to deposit 1 token.
        // Existing Balance (2) + Deposit (1) = 3 Tokens total.
        // Plan Price is 4. This should fail.
        uint256 insufficientDeposit = 1e18;

        vm.startPrank(bob);
        token.approve(address(dsc), insufficientDeposit);

        // Assert the exact custom error we expect
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__InsufficientDeposit.selector);
        dsc.reactivate(bobSubscriptionId, insufficientDeposit);
        vm.stopPrank();
    }

    /////////////////////////////
    ////// CHAINLINK TESTS //////
    /////////////////////////////

    //// TESTS FOR CHECK-UPKEEP /////

    function test_Chainlink_CheckUpkeep_ReturnFalseIfNoSubscriptions() external view {
        // Catch the return values from the checkUpkeep
        (bool upkeepNeeded, bytes memory performData) = dsc.checkUpkeep("");
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));

        assert(upkeepNeeded == false);
        assertEq(subscriptionIds.length, 0, "SubscriptionId array length should be zero");
    }

    function test_Chainlink_CheckUpkeep_ReturnFalseIfNoSubscriptionsAreDue() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Charlie subscribes to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // We did not fast forwarded the time so the interval has not been passed for the subscription

        // Catch the return values from the checkUpkeep
        (bool upkeepNeeded, bytes memory performData) = dsc.checkUpkeep("");
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));

        assert(upkeepNeeded == false);
        assertEq(subscriptionIds.length, 0, "SubscriptionId array length should be zero");
    }

    function test_Chainlink_CheckUpkeep_ReturnTrueForPartialDueSubscriptions() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Bob registers a plan
        uint256 bobPlanId = dsc.getNextPlanId();
        vm.prank(bob);
        dsc.registerPlan(address(token), PRICE_TWO, INTERVAL_TWO, "Alice Plan");

        // Charlie subscribes to Bob's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(bobPlanId, PRICE_TWO);
        vm.stopPrank();

        // Now we fast forward the time so that only the Alice's plan interval will pass
        // Now only the Charlie's subscription with Alice's plan will get triggered inside checkUpkeep
        vm.warp(block.timestamp + INTERVAL_ONE + 1);

        // Catch the return values from the checkUpkeep
        (bool upkeepNeeded, bytes memory performData) = dsc.checkUpkeep("");
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));

        assert(upkeepNeeded == true);
        assertEq(subscriptionIds.length, 1, "SubscriptionId array length should be 1");
        assertEq(subscriptionIds[0], charlieSubscriptionId, "Must have only Charlie's subscriptionId with Alice's plan");
    }

    function test_Chainlink_CheckUpkeep_ReturnTrueForAllSubscriptionsDue() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 charlieSubscriptionIdA = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Bob registers a plan
        uint256 bobPlanId = dsc.getNextPlanId();
        vm.prank(bob);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_TWO, "Alice Plan");

        uint256 charlieSubscriptionIdB = dsc.getNextSubscriptionId();
        // Charlie subscribes to Bob's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(bobPlanId, PRICE_TWO);
        vm.stopPrank();

        // Now we fast forward the time so that both intervals will pass
        vm.warp(block.timestamp + INTERVAL_TWO + 1);

        // Catch the return values from the checkUpkeep
        (bool upkeepNeeded, bytes memory performData) = dsc.checkUpkeep("");
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));

        assert(upkeepNeeded == true);
        assertEq(subscriptionIds.length, 2, "SubscriptionId array length should be 2");
        assertEq(subscriptionIds[0], charlieSubscriptionIdA, "Must have Charlie's subscriptionIdA at index 0");
        assertEq(subscriptionIds[1], charlieSubscriptionIdB, "Must have Charlie's subscriptionIdA at index 1");
    }

    //// TESTS FOR CHECK-UPKEEP /////

    function test_Chainlink_PerformUpkeep_AnyoneCanCallPerformUpkeep() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Now we fast forward the time so that the interval will pass
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Catch the return values from the checkUpkeep
        (, bytes memory performData) = dsc.checkUpkeep("");

        // Bob is calling the performUpkeep
        vm.startPrank(bob);
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionRenewed(
            charlieSubscriptionId, PRICE_ONE, 0, block.timestamp + INTERVAL_ONE
        );
        dsc.performUpkeep(performData);
        vm.stopPrank();
    }

    function test_Chainlink_PerformUpkeep_EmptyArrayShouldPassSilently() external {
        // 1. Manually construct the exact empty array payload
        // This isolates the test completely from checkUpkeep
        bytes memory emptyPerformData = abi.encode(new uint256[](0));

        // 2. Capture the state before
        uint256 activeCountBefore = dsc.getActiveSubscriptionsCount();

        // 3. Execute (If this reverts, the test fails automatically)
        dsc.performUpkeep(emptyPerformData);

        // 4. Prove that absolutely nothing changed in the contract state
        assertEq(dsc.getActiveSubscriptionsCount(), activeCountBefore, "State was unexpectedly altered on empty upkeep");
    }

    function test_Chainlink_PerformUpkeep_RevertsOnMalformedCalldata() external {
        // 1. Manually construct actual BAD calldata.
        // The contract expects an encoded uint256[].
        // We will encode a string instead. It will completely fail to decode.
        bytes memory badPerformData = abi.encode("This is definitely not an array");

        // 2. Tell Foundry that we EXPECT the transaction to revert.
        vm.expectRevert();

        // 3. Execute
        dsc.performUpkeep(badPerformData);
    }

    function test_Chainlink_PerformUpkeep_HappyPath() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Now we fast forward the time so that the interval will pass
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Catch the return values from the checkUpkeep
        (, bytes memory performData) = dsc.checkUpkeep("");

        // PRE-UPKEEP STATE CAPTURE
        DecentralizedSubscriptionService.Subscription memory sBefore = dsc.getSubscription(charlieSubscriptionId);
        uint256 providerEarningsBefore = dsc.getProviderEarnings(alice, address(token));
        uint256 activeArrayCountBefore = dsc.getActiveSubscriptionsCount();

        // Expect the event using dynamic due date calculation
        vm.expectEmit(true, false, false, true, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionRenewed(
            charlieSubscriptionId, PRICE_ONE, sBefore.balance - PRICE_ONE, sBefore.nextPaymentDue + INTERVAL_ONE
        );

        // Execute Upkeep
        dsc.performUpkeep(performData);

        // POST-UPKEEP ASSERTIONS
        DecentralizedSubscriptionService.Subscription memory sAfter = dsc.getSubscription(charlieSubscriptionId);

        // 1. Balance correctly deducted
        assertEq(sAfter.balance, sBefore.balance - PRICE_ONE, "Balance not deducted correctly");

        // 2. Next payment due advanced properly (Anchored math)
        assertEq(sAfter.nextPaymentDue, sBefore.nextPaymentDue + INTERVAL_ONE, "Due date not advanced");

        // 3. Status is still Active
        assertTrue(
            sAfter.status == DecentralizedSubscriptionService.SubscriptionStatus.Active, "Status should remain active"
        );

        // 4. Provider earnings credited
        assertEq(
            dsc.getProviderEarnings(alice, address(token)),
            providerEarningsBefore + PRICE_ONE,
            "Provider not credited for renewal"
        );

        // 5. Active array count unchanged
        assertEq(dsc.getActiveSubscriptionsCount(), activeArrayCountBefore, "Active array count changed unexpectedly");
    }

    function test_Chainlink_PerformUpkeep_InsufficientBalanceCausesLapse() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan with a balance only for one interval
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Now we fast forward the time so that the interval will pass
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Catch the return values from the checkUpkeep
        (, bytes memory performData) = dsc.checkUpkeep("");

        // Charlie's subscription will be lasped since he has no balance left
        vm.expectEmit(true, false, false, false, address(dsc));
        emit DecentralizedSubscriptionService.SubscriptionLapsed(charlieSubscriptionId);
        dsc.performUpkeep(performData);
    }

    function test_Chainlink_PerformUpkeep_MixedBatchProcessesCorrectly() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan with a balance for two intervals
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        uint256 charlieSubscriptionId = dsc.getNextSubscriptionId();
        // Charlie subscribes to Alice's plan with a balance only for one interval
        vm.startPrank(charlie);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // --- PRE-UPKEEP ASSERTIONS ---
        assertEq(dsc.getActiveSubscriptionsCount(), 2, "Should have 2 active subscriptions before upkeep");

        // Now we fast forward the time so that the first interval will pass
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Catch the return values from the checkUpkeep
        (, bytes memory performData) = dsc.checkUpkeep("");

        // Execute the mixed batch
        dsc.performUpkeep(performData);

        // POST-UPKEEP ASSERTIONS

        // 1. Array state changed correctly (shrank to 1)
        assertEq(dsc.getActiveSubscriptionsCount(), 1, "Array did not shrink after Charlie lapsed");
        assertEq(dsc.getActiveSubscriptionIdAtIndex(0), bobSubscriptionId, "Bob should remain in the active array");

        // 2. Bob's individual state (The Renew Path)
        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);
        assertTrue(
            bobSub.status == DecentralizedSubscriptionService.SubscriptionStatus.Active, "Bob should remain active"
        );
        assertEq(bobSub.balance, 0, "Bob's balance should be depleted by renewal");

        // 3. Charlie's individual state (The Lapse Path)
        DecentralizedSubscriptionService.Subscription memory charlieSub = dsc.getSubscription(charlieSubscriptionId);
        assertTrue(
            charlieSub.status == DecentralizedSubscriptionService.SubscriptionStatus.Lapsed,
            "Charlie should have lapsed due to zero balance"
        );
    }

    function test_Chainlink_PerformUpkeep_InvalidIdsAreIsolatedAndOthersContinue() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes to Alice's plan with enough balance for renewal
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO);
        dsc.subscribe(alicePlanId, PRICE_TWO);
        vm.stopPrank();

        // Fast forward time so Bob's subscription is actually due
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Construct the mixed payload manually in memory
        uint256[] memory dueIds = new uint256[](3);
        dueIds[0] = 777; // Fake ID 1
        dueIds[1] = bobSubscriptionId; // The Real, Valid ID (Sandwiched in the middle)
        dueIds[2] = 888; // Fake ID 2

        bytes memory performData = abi.encode(dueIds);

        // PRE-UPKEEP STATE CAPTURE
        uint256 bobBalanceBefore = dsc.getSubscription(bobSubscriptionId).balance;

        // We expect the contract to emit RenewalFailed for the fake IDs

        // Execute the performUpkeep.
        // If the try/catch fails to isolate, this line will revert the whole test!
        dsc.performUpkeep(performData);

        // POST-UPKEEP ASSERTIONS (THE PROOF)
        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);

        // 1. Prove Bob successfully renewed despite the bad data surrounding him
        assertEq(bobSub.balance, bobBalanceBefore - PRICE_ONE, "Bob's renewal was blocked by the invalid IDs");

        // 2. Prove Bob's due date advanced
        assertEq(bobSub.nextPaymentDue, block.timestamp + INTERVAL_ONE, "Bob's schedule did not advance");
    }

    function test_Chainlink_PerformUpkeep_ReplayingPerformDataIsNoOp() external {
        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes to Alice's plan with enough balance for renewal
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_TWO * 2);
        dsc.subscribe(alicePlanId, PRICE_TWO * 2);
        vm.stopPrank();

        // Fast forward time so Bob's subscription is due
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Catch the return values from the checkUpkeep
        (, bytes memory performData) = dsc.checkUpkeep("");

        // PRE-UPKEEP STATE CAPTURE
        uint256 bobBalanceBefore = dsc.getSubscription(bobSubscriptionId).balance;

        // Execute the performUpkeep
        dsc.performUpkeep(performData);

        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);
        assertEq(bobSub.balance, bobBalanceBefore - PRICE_ONE, "Bob's renewal was not processed properly");
        assertEq(bobSub.nextPaymentDue, block.timestamp + INTERVAL_ONE, "Bob's schedule did not advance");

        uint256 aliceEarningsBeforeReplay = dsc.getProviderEarnings(alice, address(token));
        // Execute the performUpkeep again
        dsc.performUpkeep(performData);
        DecentralizedSubscriptionService.Subscription memory bobSubA = dsc.getSubscription(bobSubscriptionId);
        assertEq(bobSubA.balance, bobSub.balance, "Bob's renewal happened twice simultaneously");
        assertEq(bobSubA.nextPaymentDue, block.timestamp + INTERVAL_ONE, "Bob's schedule advanced unnecessarily");
        assertEq(
            dsc.getProviderEarnings(alice, address(token)),
            aliceEarningsBeforeReplay,
            "Alice was credited twice for the same renewal period"
        );
    }

    function test_Chainlink_PerformUpkeep_RenewsExistingSubscriptionsOnDisabledPlan() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes with enough balance for the initial month PLUS one renewal
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE * 2);
        dsc.subscribe(alicePlanId, PRICE_ONE * 2);
        vm.stopPrank();

        // --- DISABLE PLAN ---
        vm.prank(alice);
        dsc.disablePlan(alicePlanId);

        // --- FAST FORWARD TIME ---
        // Advance time so Bob's subscription is due for renewal
        vm.warp(block.timestamp + INTERVAL_ONE);

        // --- PRE-UPKEEP STATE CAPTURE ---
        uint256 bobBalanceBefore = dsc.getSubscription(bobSubscriptionId).balance;
        uint256 aliceEarningsBefore = dsc.getProviderEarnings(alice, address(token));

        // --- EXECUTE UPKEEP ---
        (, bytes memory performData) = dsc.checkUpkeep("");
        dsc.performUpkeep(performData);

        // --- POST-UPKEEP ASSERTIONS ---
        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);

        // 1. Bob renewed successfully (balance deducted, due date advanced)
        assertEq(bobSub.balance, bobBalanceBefore - PRICE_ONE, "Balance not deducted for disabled plan renewal");
        assertEq(bobSub.nextPaymentDue, block.timestamp + INTERVAL_ONE, "Due date not advanced");
        assertTrue(
            bobSub.status == DecentralizedSubscriptionService.SubscriptionStatus.Active, "Status should remain Active"
        );

        // 2. Alice got paid despite the plan being disabled
        assertEq(
            dsc.getProviderEarnings(alice, address(token)),
            aliceEarningsBefore + PRICE_ONE,
            "Provider not credited for disabled plan renewal"
        );
    }

    ///////////////////////////////////////////
    ////// INTERNAL RENEW SUBSCRIPTION //////
    ///////////////////////////////////////////

    function test_Internal_RenewSubscription_RevertsIfNotSelfCallable() external {
        // Attempting to call the function as Bob (or any normal address)
        vm.startPrank(bob);
        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__OnlySelfCallable.selector);
        dsc._renewSubscription(1);
        vm.stopPrank();
    }

    function test_Internal_RenewSubscription_SilentReturnIfNotActive() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        dsc.cancelSubscription(bobSubscriptionId); // Status is now Cancelled
        vm.stopPrank();

        // --- TEST SILENT RETURN ---
        // Fast forward time so it would technically be "due" if it were active
        vm.warp(block.timestamp + INTERVAL_ONE);

        // Prank as the contract itself to bypass the OnlySelfCallable check
        vm.prank(address(dsc));
        dsc._renewSubscription(bobSubscriptionId);

        // Verify it silently returned without changing state back to active or lapsing
        assertTrue(
            dsc.getSubscription(bobSubscriptionId).status
                == DecentralizedSubscriptionService.SubscriptionStatus.Cancelled,
            "Silent return failed: state was altered"
        );
    }

    function test_Internal_RenewSubscription_SilentReturnIfNotDue() external {
        // --- SETUP ---
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 initialDueDate = dsc.getSubscription(bobSubscriptionId).nextPaymentDue;

        // --- TEST SILENT RETURN ---
        // We DO NOT fast forward time. It is not due yet.

        // Prank as the contract itself
        vm.prank(address(dsc));
        dsc._renewSubscription(bobSubscriptionId);

        // Verify it silently returned without advancing the due date
        assertEq(
            dsc.getSubscription(bobSubscriptionId).nextPaymentDue,
            initialDueDate,
            "Silent return failed: due date advanced"
        );
    }

    ////////////////////////////////
    ////// VIEW FUNCTIONS //////////
    ////////////////////////////////

    function test_View_GetPlan_RevertsOnInvalidId() external {
        uint256 invalidPlanId = 999;

        vm.expectRevert(DecentralizedSubscriptionService.DecentralizedSubscriptionService__PlanDoesNotExist.selector);
        dsc.getPlan(invalidPlanId);
    }

    function test_View_GetSubscription_RevertsOnInvalidId() external {
        uint256 invalidSubId = 999;

        vm.expectRevert(
            DecentralizedSubscriptionService.DecentralizedSubscriptionService__SubscriptionDoesNotExist.selector
        );
        dsc.getSubscription(invalidSubId);
    }

    function test_View_GetProviderEarnings_AccurateStates() external {
        // Initial state for Alice should be 0
        assertEq(dsc.getProviderEarnings(alice, address(token)), 0, "Initial earnings should be zero");

        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        // Bob subscribes
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Earnings should now exactly equal PRICE_ONE
        assertEq(dsc.getProviderEarnings(alice, address(token)), PRICE_ONE, "Earnings not updated after subscribe");

        // Random third party (Charlie) should have 0 earnings
        assertEq(dsc.getProviderEarnings(charlie, address(token)), 0, "Non-provider has earnings");
    }

    function test_View_GetActiveSubscriptionsCount_AccurateStates() external {
        // Initial count should be 0
        assertEq(dsc.getActiveSubscriptionsCount(), 0, "Initial count not zero");

        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();

        // Bob subscribes
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        // Count should go to 1
        assertEq(dsc.getActiveSubscriptionsCount(), 1, "Count did not increment on subscribe");

        // Bob cancels
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);

        // Count should go back to 0
        assertEq(dsc.getActiveSubscriptionsCount(), 0, "Count did not decrement on cancel");
    }

    /////////////////////////////
    //////// FUZZ TESTS /////////
    /////////////////////////////

    function testFuzz_Subscribe_BalanceMatchesDepositMinusPrice(uint256 depositAmount) external {
        depositAmount = bound(depositAmount, PRICE_ONE, STARTING_TOKEN_BALANCE);

        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), depositAmount);
        dsc.subscribe(alicePlanId, depositAmount);
        vm.stopPrank();

        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);

        assertEq(bobSub.balance, depositAmount - PRICE_ONE, "Bob's balance is not updated properly");
    }

    function testFuzz_TopUp_BalanceIncreasesByExactTopUpAmount(uint256 topUpAmount) external {
        topUpAmount = bound(topUpAmount, PRICE_ONE, STARTING_TOKEN_BALANCE / 4);

        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), PRICE_ONE);
        dsc.subscribe(alicePlanId, PRICE_ONE);
        vm.stopPrank();

        uint256 balanceBefore = dsc.getSubscription(bobSubscriptionId).balance;
        // Top-up
        vm.startPrank(bob);
        token.approve(address(dsc), topUpAmount);
        dsc.topUp(bobSubscriptionId, topUpAmount);
        vm.stopPrank();

        uint256 balanceAfter = dsc.getSubscription(bobSubscriptionId).balance;
        assertEq(balanceAfter - balanceBefore, topUpAmount, "TopUp delta should equal topUp amount");
    }

    function testFuzz_SubscribeAndCancel_RefundMaintainsExactTokenAccounting(uint256 depositAmount) external {
        depositAmount = bound(depositAmount, PRICE_ONE, STARTING_TOKEN_BALANCE);

        // Alice registers a plan
        uint256 alicePlanId = dsc.getNextPlanId();
        vm.prank(alice);
        dsc.registerPlan(address(token), PRICE_ONE, INTERVAL_ONE, "Alice Plan");

        uint256 bobTokenBefore = token.balanceOf(bob);
        uint256 bobSubscriptionId = dsc.getNextSubscriptionId();
        // Bob subscribes to Alice's plan
        vm.startPrank(bob);
        token.approve(address(dsc), depositAmount);
        dsc.subscribe(alicePlanId, depositAmount);
        vm.stopPrank();

        uint256 bobBalanceAfterSubscribing = token.balanceOf(bob);
        DecentralizedSubscriptionService.Subscription memory bobSub = dsc.getSubscription(bobSubscriptionId);

        // Bob the immediately cancles subscription to Alice's plan
        vm.prank(bob);
        dsc.cancelSubscription(bobSubscriptionId);
        DecentralizedSubscriptionService.Subscription memory bobSubAfCan = dsc.getSubscription(bobSubscriptionId);
        uint256 providersUnWithdrawnEarnings = dsc.getProviderEarnings(alice, address(token));
        uint256 contractTokenBalance = token.balanceOf(address(dsc));

        assertEq(
            bobSub.balance, depositAmount - PRICE_ONE, "Bob's subscription balance is not updated properly after topUp"
        );
        assertEq(
            bobBalanceAfterSubscribing,
            STARTING_TOKEN_BALANCE - depositAmount,
            "Bob's token balance is not updated properly after subscription"
        );
        assertEq(bobSubAfCan.balance, 0, "Bob's subscription balance is not updated properly after cancel");
        assertEq(
            bobTokenBefore - token.balanceOf(bob),
            PRICE_ONE,
            "Bob's net token loss should equal exactly one period's price"
        );
        assertEq(
            contractTokenBalance,
            providersUnWithdrawnEarnings,
            "Providers unwithdrawn earnings are not matching correctly with contracts balance"
        );
    }
}
