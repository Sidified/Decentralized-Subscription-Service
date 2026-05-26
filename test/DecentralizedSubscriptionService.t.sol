// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
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
}
