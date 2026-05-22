# Decentralized Subscription Service (Work In Progress)

A Solidity + Foundry + Chainlink Automation practice project focused on:

- protocol architecture
- iterable state design
- accounting invariants
- Chainlink Automation
- scalable storage patterns
- failure isolation
- adversarial thinking
- smart contract security

---

# Overview

This project implements a decentralized subscription management system where:

- service providers create subscription plans
- users subscribe using ERC20 tokens
- the contract escrows user funds
- Chainlink Automation autonomously renews subscriptions
- subscriptions automatically lapse when balances become insufficient

The contract itself acts as the custodian of all deposited funds.

Users prepay using ERC20 tokens, and the protocol internally moves accounting balances during renewals.

---

# Core Concepts

## Providers

Providers can:

- register plans
- disable plans
- withdraw accumulated earnings

---

## Users

Users can:

- subscribe to plans
- top up active subscriptions
- cancel subscriptions
- reactivate lapsed subscriptions

---

## Chainlink Automation

Chainlink Automation:

- checks which subscriptions are due
- processes renewals autonomously

---

# Subscription Model

Each subscription belongs to:

```text
user + plan
```

A subscription contains:

- subscriber
- planId
- escrowed balance
- next payment due timestamp
- subscription status

The contract never duplicates plan information inside subscriptions.

Everything derives through:

```text
subscription -> planId -> plan
```

---

# Plan Model

Each plan contains:

- provider
- ERC20 token
- price
- billing interval
- active/inactive status
- plan name

Plans are immutable after creation.

Only the active flag can change.

---

# Subscription Lifecycle

---

## 1. Provider Registers Plan

Provider creates a plan with:

- token
- price
- interval
- name

Example:

```text
Netflix Premium
10 USDC
30 days
```

---

## 2. User Subscribes

User deposits ERC20 tokens into the contract.

This project uses a:

```text
pay-upfront
```

model.

Meaning:

- the first payment is charged immediately
- only future-renewal funds remain in subscription balance

Example:

```text
deposit = 100
price = 10
```

Then:

```text
provider earnings += 10
subscription.balance = 90
nextPaymentDue = now + interval
```

---

## 3. Chainlink Renewal

When:

```text
block.timestamp >= nextPaymentDue
```

Chainlink renews the subscription.

Renewal:

```text
subscription.balance -= price
provider earnings += price
nextPaymentDue += interval
```

---

## 4. Lapse

If:

```text
subscription.balance < plan.price
```

then:

- subscription becomes Lapsed
- removed from active renewal tracking

---

## 5. Reactivation

Lapsed subscriptions may reactivate at any time.

Reactivation behaves exactly like subscribe:

```text
provider earnings += price
subscription.balance = deposit - price
nextPaymentDue = now + interval
status = Active
```

No grace window exists in v1.

---

## 6. Cancellation

Users may cancel subscriptions.

Cancellation:

- refunds only remaining balance
- current billing period is non-refundable
- removes subscription from active tracking
- marks subscription Cancelled permanently

Cancelled subscriptions are terminal.

---

# Storage Architecture

---

# Plan Storage

```solidity
mapping(uint256 => Plan) s_plans;
```

---

# Subscription Storage

```solidity
mapping(uint256 => Subscription) s_subscriptions;
```

---

# User+Plan Lookup

```solidity
mapping(address => mapping(uint256 => uint256))
    s_userPlanToSubscriptionId;
```

Used for:

```text
Does this user already have a subscription to this plan?
```

---

# Active Subscription Tracking

```solidity
uint256[] s_activeSubscriptionIds;
```

Needed because Solidity mappings are not iterable.

Chainlink Automation scans this array during:

```text
checkUpkeep()
```

---

# O(1) Array Removal

To support efficient removal:

```solidity
mapping(uint256 => uint256)
    s_subscriptionIdToArrayIndex;
```

Uses:

```text
swap-and-pop
```

pattern.

---

# ID Design

Plan IDs and Subscription IDs are independent.

```solidity
uint256 s_nextPlanId = 1;
uint256 s_nextSubscriptionId = 1;
```

IDs start at 1 so:

```text
0 = does not exist
```

can be used safely.

---

# Chainlink Automation Design

---

# checkUpkeep()

Runs OFF-CHAIN.

Responsibilities:

- iterate active subscriptions
- find due subscriptions
- return encoded due subscription IDs

This keeps expensive iteration off-chain.

---

# performUpkeep()

Runs ON-CHAIN.

Responsibilities:

- re-verify all subscription conditions
- process renewals
- lapse insufficient subscriptions

Important:

```text
performUpkeep NEVER trusts calldata
```

All conditions are re-validated on-chain.

---

# Failure Isolation

Renewals are batch processed.

Without isolation:

```text
1 reverting subscription
=
whole upkeep revert
```

This creates a denial-of-service risk.

To isolate failures:

```solidity
try this._renewSubscription(subId) {

} catch {

}
```

Each renewal failure becomes isolated.

One malicious subscription cannot break the entire system.

---

# Token Handling

---

# Fee-On-Transfer Tokens

Not supported.

FoT detection uses:

```text
balanceBefore
transferFrom
balanceAfter
```

and verifies:

```text
received == expected
```

---

# Token Whitelist

No token whitelist exists in v1.

Providers may register any ERC20 token.

Users are responsible for verifying token legitimacy before subscribing.

---

# Malicious ERC20 Assumption

The protocol assumes reasonably well-behaved ERC20 tokens.

Completely malicious token contracts cannot be fully defended against.

This is a documented trust assumption.

---

# Security Design

---

# CEI Pattern

Critical flows follow:

```text
Checks
Effects
Interactions
```

Especially:

- provider withdrawals
- renewal processing

---

# Reentrancy Protection

Provider withdrawals use:

- CEI
- nonReentrant

Earnings are zeroed before transfers.

---

# Double-Charge Protection

A subscription cannot renew twice in the same billing period.

Protection mechanism:

```text
nextPaymentDue += interval
```

before external interactions.

---

# State Isolation

Each subscription is isolated by:

```text
subscription -> planId -> token
```

One subscription cannot accidentally drain another subscription's token balance.

---

# Invariants

---

## 1. Token Accounting Invariant

For each token:

```text
contract token balance
==
sum(subscription balances)
+
sum(provider unwithdrawn earnings)
```

---

## 2. Cancelled Is Terminal

Cancelled subscriptions can never become Active again.

---

## 3. nextPaymentDue Only Moves Forward

Due dates are monotonic.

---

## 4. Plan Immutability

After creation:

- price
- interval
- token

never change.

---

## 5. No Double Charge

A subscription cannot renew twice within the same billing interval.

---

# Threat Model

---

## Batch DoS Attack

One malicious subscription attempts to revert upkeep batch.

Mitigation:

- per-subscription try/catch isolation

---

## Reentrancy During Withdrawals

Malicious token attempts reentrancy during transfer.

Mitigation:

- CEI
- nonReentrant

---

## Active Array Corruption

Duplicate IDs or stale IDs inside active array.

Mitigation:

- strict add/remove paths
- index mapping consistency

---

## Malicious ERC20 Behavior

Token changes behavior after subscription.

Mitigation:

- documented trust assumption only

---

## Extreme Parameters

Examples:

- interval = 1 second
- absurdly large prices

Mitigation:

- sanity checks
- edge-case testing

---

# Function List

---

# Provider Functions

## registerPlan(...)

Creates new immutable plan.

---

## disablePlan(uint256 planId)

Disables new subscriptions only.

Existing subscriptions continue renewing.

---

## withdrawProviderEarnings(address token)

Withdraws accumulated provider earnings.

---

# User Functions

## subscribe(uint256 planId, uint256 depositAmount)

Creates subscription using pay-upfront model.

---

## topUp(uint256 subscriptionId, uint256 amount)

Adds funds to ACTIVE subscription only.

Does NOT auto-reactivate lapsed subscriptions.

---

## cancelSubscription(uint256 subscriptionId)

Cancels permanently and refunds remaining balance.

---

## reactivate(uint256 subscriptionId, uint256 depositAmount)

Reactivates Lapsed subscription using pay-upfront logic.

---

# Chainlink Functions

## checkUpkeep(bytes calldata)

Finds due subscriptions off-chain.

---

## performUpkeep(bytes calldata)

Processes renewals on-chain.

---

# Events

```solidity
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
    uint256 indexed subscriptionId,
    address indexed subscriber,
    uint256 indexed planId,
    uint256 initialDeposit
);

event SubscriptionToppedUp(
    uint256 indexed subscriptionId,
    uint256 amount,
    uint256 newBalance
);

event SubscriptionRenewed(
    uint256 indexed subscriptionId,
    uint256 amountCharged,
    uint256 newBalance,
    uint256 newDueTime
);

event SubscriptionLapsed(uint256 indexed subscriptionId);

event SubscriptionReactivated(
    uint256 indexed subscriptionId,
    uint256 newDeposit
);

event SubscriptionCancelled(
    uint256 indexed subscriptionId,
    uint256 refundAmount
);

event ProviderEarningsWithdrawn(
    address indexed provider,
    address indexed token,
    uint256 amount
);

event RenewalFailed(uint256 indexed subscriptionId);
```

---

# Key Engineering Lessons

This project is primarily about:

- iterable state design
- accounting correctness
- automation-safe architecture
- gas-aware storage patterns
- lifecycle management
- adversarial thinking
- batch failure isolation
- invariant-driven development
- scalable Solidity systems

---

# Out of Scope (v1)

Not included in this version:

- token whitelisting
- admin controls
- upgradeability
- mutable plans
- provider reputation
- off-chain service verification
- NFT subscriptions
- cross-chain support

---

# Tech Stack

- Solidity
- Foundry
- Chainlink Automation
- OpenZeppelin Contracts

---

# Testing Focus

- unit tests
- invariant tests
- fuzz tests
- lifecycle transition tests
- accounting correctness tests
- automation edge-case tests
- failure isolation tests

---

# Project Goal

The goal of this project is NOT merely to build a subscription contract.

The real purpose is learning:

- how production protocols structure state
- how automated systems interact with contracts
- how accounting invariants protect funds
- how to think adversarially
- how to design scalable Solidity architectures
- how to reason about lifecycle correctness