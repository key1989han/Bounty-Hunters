// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";
import "./MockV3Aggregator.sol";

/// @notice Foundry tests covering PriceOracle validation and fallback behavior.
contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockV3Aggregator public primary;
    MockV3Aggregator public fallbackFeed;

    uint8 constant DECIMALS = 8;
    int256 constant VALID_PRICE = 2000e8;
    int256 constant FALLBACK_PRICE = 1999e8;

    event StalePrice(uint256 lastUpdate, uint256 currentTime);
    event PriceQueried(int256 price, uint256 timestamp);

    function setUp() public {
        primary = new MockV3Aggregator(DECIMALS, VALID_PRICE);
        fallbackFeed = new MockV3Aggregator(DECIMALS, FALLBACK_PRICE);
        oracle = new PriceOracle(address(primary), address(fallbackFeed));
    }

    /// @dev Scenario 1: valid fresh price from primary
    function test_validPrice() public {
        int256 price = oracle.getLatestPrice();
        assertEq(price, VALID_PRICE);
    }

    /// @dev Scenario 2: stale primary triggers fallback + StalePrice event
    function test_stalePriceTriggersFallback() public {
        uint256 staleTime = block.timestamp - 3601;
        primary.updateRoundData(1, VALID_PRICE, staleTime, staleTime, 1);
        // Keep fallback fresh
        fallbackFeed.updateRoundData(1, FALLBACK_PRICE, block.timestamp, block.timestamp, 1);

        vm.expectEmit(true, true, true, true);
        emit StalePrice(staleTime, block.timestamp);

        int256 price = oracle.getLatestPrice();
        assertEq(price, FALLBACK_PRICE);
    }

    /// @dev Scenario 3: zero/negative prices must REVERT (not return false)
    function test_negativePriceReverts() public {
        primary.updateAnswer(-1);
        vm.expectRevert(bytes("Invalid price"));
        oracle.getLatestPrice();
    }

    function test_zeroPriceReverts() public {
        primary.updateAnswer(0);
        vm.expectRevert(bytes("Invalid price"));
        oracle.getLatestPrice();
    }

    /// @dev Scenario 4: incomplete round is rejected
    function test_incompleteRoundRejected() public {
        // answeredInRound < roundId
        primary.updateRoundData(5, VALID_PRICE, block.timestamp, block.timestamp, 4);
        vm.expectRevert(bytes("Incomplete round"));
        oracle.getLatestPrice();
    }

    /// @dev Scenario 5: both oracles stale -> revert
    function test_bothOraclesStaleReverts() public {
        uint256 staleTime = block.timestamp - 7200;
        primary.updateRoundData(1, VALID_PRICE, staleTime, staleTime, 1);
        fallbackFeed.updateRoundData(1, FALLBACK_PRICE, staleTime, staleTime, 1);

        vm.expectRevert(bytes("Stale price"));
        oracle.getLatestPrice();
    }

    function test_maxStalenessConfigurableByOwner() public {
        oracle.setMaxStaleness(7200);
        assertEq(oracle.MAX_STALENESS(), 7200);

        // Price updated 4000s ago is stale under 3600 but fresh under 7200
        uint256 t = block.timestamp - 4000;
        primary.updateRoundData(1, VALID_PRICE, t, t, 1);
        int256 price = oracle.getLatestPrice();
        assertEq(price, VALID_PRICE);
    }

    function test_nonOwnerCannotSetMaxStaleness() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(bytes("Not owner"));
        oracle.setMaxStaleness(100);
    }
}
