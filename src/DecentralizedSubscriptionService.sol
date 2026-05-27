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
    error DecentralizedSubscriptionService__AmountMustBeNonZero();

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

    //// STATE VARIABLES ////

    mapping(uint256 => Plan) private s_plans;
    mapping(address => uint256[]) private s_providerPlanIds;
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

        s_providerPlanIds[msg.sender].push(newPlanId);

        s_nextPlanId = newPlanId + 1; // increment the counter

        emit PlanRegistered(newPlanId, msg.sender, token, price, interval, name);
    }

    function disablePlan(uint256 planId) external {
        _validatePlanId(planId);
        Plan storage p = s_plans[planId];

        if (msg.sender != p.provider) revert DecentralizedSubscriptionService__NotPlanOwner();
        if (p.isActive == false) revert DecentralizedSubscriptionService__PlanNotActive();

        p.isActive = false; // change the active status of the plan from true to false

        emit PlanDisabled(planId);
    }

    function withdrawProviderEarnings(address token) external nonReentrant {
        // Checks
        if (s_providerEarnings[msg.sender][token] == 0) {
            revert DecentralizedSubscriptionService__NoEarningsToWithdraw();
        }

        // Effects
        uint256 providerEarning = s_providerEarnings[msg.sender][token];
        s_providerEarnings[msg.sender][token] = 0;

        // Interactions
        SafeERC20.safeTransfer(IERC20(token), msg.sender, providerEarning);

        emit ProviderEarningsWithdrawn(msg.sender, token, providerEarning);
    }

    //// USER'S FUNCTIONS ////
    function subscribe(uint256 planId, uint256 depositAmount) external nonReentrant {
        // Checks
        _validatePlanId(planId);
        Plan storage p = s_plans[planId];
        if (p.isActive == false) revert DecentralizedSubscriptionService__PlanNotActive();
        if (s_userPlanToSubscriptionId[msg.sender][planId] != 0) {
            revert DecentralizedSubscriptionService__AlreadySubscribed();
        }
        if (depositAmount < p.price) revert DecentralizedSubscriptionService__InsufficientDeposit();

        // Effects
        s_providerEarnings[p.provider][p.token] += p.price;
        uint256 newSubscriptionId = s_nextSubscriptionId;
        s_subscriptions[newSubscriptionId] = Subscription({
            subscriber: msg.sender,
            planId: planId,
            balance: depositAmount - p.price,
            nextPaymentDue: block.timestamp + p.interval,
            status: SubscriptionStatus.Active
        });
        s_nextSubscriptionId = newSubscriptionId + 1;

        s_userPlanToSubscriptionId[msg.sender][planId] = newSubscriptionId;

        _addToActiveArray(newSubscriptionId);

        // Interactions
        IERC20 planToken = IERC20(p.token);
        _pullTokensWithFotCheck(planToken, msg.sender, depositAmount);
        emit SubscriptionCreated(newSubscriptionId, msg.sender, planId, depositAmount);
    }

    function topUp(uint256 subscriptionId, uint256 amount) external nonReentrant {
        // Checks
        _validateSubscriptionId(subscriptionId);
        Subscription storage s = s_subscriptions[subscriptionId];
        if (s.subscriber != msg.sender) revert DecentralizedSubscriptionService__NotSubscriptionOwner();
        if (s.status != SubscriptionStatus.Active) revert DecentralizedSubscriptionService__SubscriptionNotActive();
        if (amount == 0) revert DecentralizedSubscriptionService__AmountMustBeNonZero();

        // Effects
        s.balance += amount;

        // Interactions
        Plan storage p = s_plans[s.planId];
        IERC20 planToken = IERC20(p.token);
        _pullTokensWithFotCheck(planToken, msg.sender, amount);

        emit SubscriptionToppedUp(subscriptionId, amount, s.balance);
    }

    function cancelSubscription(uint256 subscriptionId) external nonReentrant {
        // Checks
        _validateSubscriptionId(subscriptionId);
        Subscription storage s = s_subscriptions[subscriptionId];
        Plan storage p = s_plans[s.planId];
        if (s.subscriber != msg.sender) revert DecentralizedSubscriptionService__NotSubscriptionOwner();
        if (s.status == SubscriptionStatus.Cancelled) {
            revert DecentralizedSubscriptionService__SubscriptionAlreadyCancelled();
        }

        // Effects
        if (s.status == SubscriptionStatus.Active) {
            // Lapsed Subscriptions are already removed from the active subscriptions array
            _removeFromActiveArray(subscriptionId);
        }
        s.status = SubscriptionStatus.Cancelled;

        // Clear the mapping
        delete s_userPlanToSubscriptionId[msg.sender][s.planId];

        uint256 balance = s.balance;
        s.balance = 0;

        // Interactions
        if (balance != 0) {
            IERC20 planToken = IERC20(p.token);
            SafeERC20.safeTransfer(planToken, msg.sender, balance);
        }

        emit SubscriptionCancelled(subscriptionId, balance);
    }

    function reactivate(uint256 subscriptionId, uint256 depositAmount) external nonReentrant {
        // Checks
        _validateSubscriptionId(subscriptionId);
        Subscription storage s = s_subscriptions[subscriptionId];
        Plan storage p = s_plans[s.planId];
        if (msg.sender != s.subscriber) revert DecentralizedSubscriptionService__NotSubscriptionOwner();
        if (s.status != SubscriptionStatus.Lapsed) revert DecentralizedSubscriptionService__SubscriptionNotLapsed();
        if (p.isActive == false) revert DecentralizedSubscriptionService__PlanNotActive();
        // Reactivation carries forward any unspent balance from the lapsed subscription,
        // so the user only needs to deposit enough to bring (existing + deposit) >= price.
        if (depositAmount + s.balance < p.price) revert DecentralizedSubscriptionService__InsufficientDeposit();

        // Effects
        s_providerEarnings[p.provider][p.token] += p.price;
        s.status = SubscriptionStatus.Active;
        s.balance = s.balance + depositAmount - p.price;
        s.nextPaymentDue = block.timestamp + p.interval;

        _addToActiveArray(subscriptionId);

        // Interactions
        IERC20 planToken = IERC20(p.token);
        _pullTokensWithFotCheck(planToken, msg.sender, depositAmount);

        emit SubscriptionReactivated(subscriptionId, depositAmount);
    }

    //// CHAINLINK FUNCTIONS ////
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        // Pass 1: count
        uint256 count = 0;
        for (uint256 i = 0; i < s_activeSubscriptionIds.length; i++) {
            uint256 id = s_activeSubscriptionIds[i];
            if (s_subscriptions[id].nextPaymentDue <= block.timestamp) {
                count++;
            }
        }

        // Pass 2: fill
        uint256[] memory dueIds = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < s_activeSubscriptionIds.length; i++) {
            uint256 id = s_activeSubscriptionIds[i];
            if (s_subscriptions[id].nextPaymentDue <= block.timestamp) {
                dueIds[j] = id;
                j++;
            }
        }

        upkeepNeeded = count > 0;
        performData = abi.encode(dueIds);

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            try this._renewSubscription(subscriptionIds[i]) {
            // success — _renewSubscription emitted its own event
            }
            catch {
                emit RenewalFailed(subscriptionIds[i]);
            }
        }
    }

    // INTERNAL LOGIC EXPOSED AS EXTERNAL (for try/catch isolation)
    function _renewSubscription(uint256 subscriptionId) external {
        // Only callable by this contract (self-external-call pattern)
        if (msg.sender != address(this)) revert DecentralizedSubscriptionService__OnlySelfCallable();
        _validateSubscriptionId(subscriptionId);
        Subscription storage s = s_subscriptions[subscriptionId];
        if (s.status != SubscriptionStatus.Active) return;
        if (s.nextPaymentDue > block.timestamp) return;

        Plan storage p = s_plans[s.planId];
        if (s.balance >= p.price) {
            // Renew: debit subscription, credit provider, advance due date by interval
            // so Chainlink lateness doesn't drift the schedule.
            s.balance -= p.price;
            s.nextPaymentDue += p.interval;
            s_providerEarnings[p.provider][p.token] += p.price;

            emit SubscriptionRenewed(subscriptionId, p.price, s.balance, s.nextPaymentDue);
        } else {
            // Lapse: status change + remove from active array. Balance is preserved
            // for reactivate (carry-forward) or cancel (refund).
            s.status = SubscriptionStatus.Lapsed;
            _removeFromActiveArray(subscriptionId);

            emit SubscriptionLapsed(subscriptionId);
        }
    }

    //// INTERNAL FUNCTIONS ////

    /// @dev Pull tokens from `from` into the contract, reverting if the
    ///      received amount differs from `amount` (fee-on-transfer detection).
    function _pullTokensWithFotCheck(IERC20 token, address from, uint256 amount) internal {
        uint256 balanceBefore = token.balanceOf(address(this));
        SafeERC20.safeTransferFrom(token, from, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - balanceBefore != amount) {
            revert DecentralizedSubscriptionService__FeeOnTransferNotSupported();
        }
    }

    /// @dev Reverts if planId is 0 or not yet assigned. Use before reading s_plans[planId].
    function _validatePlanId(uint256 planId) internal view {
        if (planId == 0 || planId >= s_nextPlanId) {
            revert DecentralizedSubscriptionService__PlanDoesNotExist();
        }
    }

    /// @dev Reverts if subscriptionId is 0 or not yet assigned. Use before reading s_subscriptions[subscriptionId].
    function _validateSubscriptionId(uint256 subscriptionId) internal view {
        if (subscriptionId == 0 || subscriptionId >= s_nextSubscriptionId) {
            revert DecentralizedSubscriptionService__SubscriptionDoesNotExist();
        }
    }

    function _addToActiveArray(uint256 subscriptionId) internal {
        uint256 newIndex = s_activeSubscriptionIds.length;
        s_activeSubscriptionIds.push(subscriptionId); // this step will increase the s_activeSubscriptionIds's length
        s_subscriptionIdToArrayIndex[subscriptionId] = newIndex;
    }

    /// @dev Removes `subscriptionId` from the active array using swap-and-pop.
    ///      Caller MUST ensure the ID is present in the array; calling on a
    ///      non-existent ID will corrupt array state.
    function _removeFromActiveArray(uint256 subscriptionId) internal {
        uint256 indexToRemove = s_subscriptionIdToArrayIndex[subscriptionId];
        uint256 lastIndex = s_activeSubscriptionIds.length - 1;
        uint256 lastId = s_activeSubscriptionIds[lastIndex];

        // Move the last element into the removed slot
        s_activeSubscriptionIds[indexToRemove] = lastId;
        // Update the mapping for the moved element
        s_subscriptionIdToArrayIndex[lastId] = indexToRemove;

        // Pop the (now duplicate) last element
        s_activeSubscriptionIds.pop();
        // Clear the removed subscription's mapping entry
        delete s_subscriptionIdToArrayIndex[subscriptionId];
    }

    //// VIEW FUNCTIONS ////
    function getPlan(uint256 planId) external view returns (Plan memory) {
        _validatePlanId(planId);
        return s_plans[planId];
    }

    function getProviderPlanIds(address provider) external view returns (uint256[] memory) {
        return s_providerPlanIds[provider];
    }

    function getNextPlanId() external view returns (uint256) {
        return s_nextPlanId;
    }

    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {
        _validateSubscriptionId(subscriptionId);
        return s_subscriptions[subscriptionId];
    }

    function getProviderEarnings(address provider, address token) external view returns (uint256) {
        return s_providerEarnings[provider][token];
    }

    function getActiveSubscriptionsCount() external view returns (uint256) {
        return s_activeSubscriptionIds.length;
    }

    function getUserSubscriptionId(address user, uint256 planId) external view returns (uint256) {
        _validatePlanId(planId);
        return s_userPlanToSubscriptionId[user][planId];
    }
}

