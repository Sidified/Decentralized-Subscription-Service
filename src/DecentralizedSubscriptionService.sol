// SPDX-License-Identifier: MIT
// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

///// VERSION ////
pragma solidity ^0.8.20;

//// IMPORTS ////
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract DecentralizedSubscriptionService is ReentrancyGuard, AutomationCompatibleInterface {
    //// ERRORS ////
    error DecentralizedSubscriptionService__PlanDoesNotExist();
    error DecentralizedSubscriptionService__PlanNotActive();
    error DecentralizedSubscriptionService__PlanPriceMustBeNonZero();
    error DecentralizedSubscriptionService__PlanIntervalMustBeNonZero();
    error DecentralizedSubscriptionService__InvalidTokenAddress();
    error DecentralizedSubscriptionService__NotPlanOwner();
    error DecentralizedSubscriptionService__SubscriptionDoesNotExist();
    error DecentralizedSubscriptionService__NotSubscriptionOwner();
    error DecentralizedSubscriptionService__SubscriptionNotActive();
    error DecentralizedSubscriptionService__SubscriptionNotLapsed();
    error DecentralizedSubscriptionService__SubscriptionAlreadyCancelled();
    error DecentralizedSubscriptionService__AlreadySubscribed();
    error DecentralizedSubscriptionService__InsufficientDeposit();
    error DecentralizedSubscriptionService__FeeOnTransferNotSupported();
    error DecentralizedSubscriptionService__NoEarningsToWithdraw();
    error DecentralizedSubscriptionService__OnlySelfCallable();

    //// TYPE DECLARATIONS ////

    //// ENUMS ////
    enum SubscriptionStatus {
        Active,
        Lapsed,
        Cancelled
    }

    //// STRUCTS ////
    struct Plan {
        address provider;
        address token;
        uint256 price;
        uint256 interval;
        bool isActive;
        string name;
    }

    struct Subscription {
        address subscriber;
        uint256 planId;
        uint256 balance;
        uint256 nextPaymentDue;
        SubscriptionStatus status;
    }

    //// STATE VARIABLE ////

    mapping(uint256 => Plan) private s_plans;
    mapping(uint256 => Subscription) private s_subscriptions;
    mapping(address => mapping(uint256 => uint256)) private s_userPlanToSubscriptionId;
    mapping(address => mapping(address => uint256)) private s_providerEarnings;

    uint256[] private s_activeSubscriptionIds;
    mapping(uint256 => uint256) private s_subscriptionIdToArrayIndex;

    uint256 private s_nextPlanId; // initialized to 1 in constructor
    uint256 private s_nextSubscriptionId; // initialized to 1 in constructor

    //// EVENTS ////

    event PlanRegistered(
        uint256 indexed planId,
        address indexed provider,
        address indexed token,
        uint256 price,
        uint256 interval,
        string name
    );
    event PlanDisabled(uint256 indexed planId);
    event SubscriptionCreated(
        uint256 indexed subscriptionId, address indexed subscriber, uint256 indexed planId, uint256 initialDeposit
    );
    event SubscriptionToppedUp(uint256 indexed subscriptionId, uint256 amount, uint256 newBalance);
    event SubscriptionRenewed(
        uint256 indexed subscriptionId, uint256 amountCharged, uint256 newBalance, uint256 newDueTime
    );
    event SubscriptionLapsed(uint256 indexed subscriptionId);
    event SubscriptionReactivated(uint256 indexed subscriptionId, uint256 newDeposit);
    event SubscriptionCancelled(uint256 indexed subscriptionId, uint256 refundAmount);
    event ProviderEarningsWithdrawn(address indexed provider, address indexed token, uint256 amount);
    event RenewalFailed(uint256 indexed subscriptionId);

    //// FUNCTIONS ////

    //// CONSTRUCTOR ////
    constructor() {
        s_nextPlanId = 1;
        s_nextSubscriptionId = 1;
    }

    //// EXTERNAL FUNCTIONS ////

    //// PROVIDER'S FUNCTIONS ////
    function registerPlan(address token, uint256 price, uint256 interval, string memory name) external {
        if (token == address(0)) revert DecentralizedSubscriptionService__InvalidTokenAddress();
        if (price == 0) revert DecentralizedSubscriptionService__PlanPriceMustBeNonZero();
        if (interval == 0) revert DecentralizedSubscriptionService__PlanIntervalMustBeNonZero();

        uint256 newPlanId = s_nextPlanId; // read first
        s_plans[newPlanId] =
            Plan({provider: msg.sender, token: token, price: price, interval: interval, isActive: true, name: name}); // write the plan

        s_nextPlanId = newPlanId + 1; // increment the counter

        emit PlanRegistered(newPlanId, msg.sender, token, price, interval, name); // emith the event
    }

    function disablePlan(uint256 planId) external {}

    function withdrawProviderEarnings(address token) external {}

    //// USER'S FUNCTIONS ////
    function subscribe(uint256 planId, uint256 depositAmount) external {}

    function topUp(uint256 subscriptionId, uint256 amount) external {}

    function cancelSubscription(uint256 subscriptionId) external {}

    function reactivate(uint256 subscriptionId, uint256 depositAmount) external {}

    //// CHAINLINK FUNCTIONS ////
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {}

    function performUpkeep(bytes calldata performData) external override {}

    // INTERNAL LOGIC EXPOSED AS EXTERNAL (for try/catch isolation)
    function _renewSubscription(uint256 subscriptionId) external {
        // Only callable by this contract (self-external-call pattern)
    }

    //// INTERNAL FUNCTIONS ////

    /// @dev Pull tokens from `from` into the contract, reverting if the
    ///      received amount differs from `amount` (fee-on-transfer detection).
    function _pullTokensWithFotCheck(address token, address from, uint256 amount) internal {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - balanceBefore != amount) {
            revert DecentralizedSubscriptionService__FeeOnTransferNotSupported();
        }
    }

    function _addToActiveArray(uint256 subscriptionId) internal {}

    function _removeFromActiveArray(uint256 subscriptionId) internal {}

    //// VIEW FUNCTIONS ////
    function getPlan(uint256 planId) external view returns (Plan memory) {}

    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {}

    function getProviderEarnings(address provider, address token) external view returns (uint256) {}

    function getActiveSubscriptionsCount() external view returns (uint256) {}

    function getUserSubscriptionId(address user, uint256 planId) external view returns (uint256) {}
}

