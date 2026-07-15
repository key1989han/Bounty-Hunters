// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";

/// @notice Minimal mock of Chainlink AggregatorV3Interface for testing
contract MockAggregator is AggregatorV3Interface {
    uint8 public _decimals = 8;
    uint80 public roundId;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public answeredInRound;
    bool public shouldRevert = false;

    function setPrice(int256 _price, uint256 _timestamp, uint80 _roundId, uint80 _answeredInRound) external {
        answer = _price;
        updatedAt = _timestamp;
        roundId = _roundId;
        answeredInRound = _answeredInRound;
    }

    function setRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function latestRoundData() external view override returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        if (shouldRevert) {
            revert("Mock revert");
        }
        return (roundId, answer, block.timestamp, updatedAt, answeredInRound);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }
}

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockAggregator public primary;
    MockAggregator public fallback;
    address public owner;

    function setUp() public {
        owner = address(this);
        primary = new MockAggregator();
        fallback = new MockAggregator();
        oracle = new PriceOracle(address(primary), address(fallback));

        // Set valid defaults for primary
        primary.setPrice(2000e8, block.timestamp, 1, 1);
        // Set valid defaults for fallback
        fallback.setPrice(2001e8, block.timestamp, 1, 1);
    }

    /// @notice Test 1: Valid price returns correctly
    function test_validPrice() public view {
        int256 price = oracle.getLatestPrice();
        assertEq(price, 2000e8, "Should return primary oracle price");
    }

    /// @notice Test 2: Stale price (>1 hour old) reverts
    function test_stalePriceReverts() public {
        // Set primary to 2 hours ago (stale)
        primary.setPrice(2000e8, block.timestamp - 7200, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.StalePriceError.selector, block.timestamp - 7200));
        oracle.getLatestPrice();
    }

    /// @notice Test 3: Negative price reverts
    function test_negativePriceReverts() public {
        primary.setPrice(-100, block.timestamp, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector));
        oracle.getLatestPrice();
    }

    /// @notice Test 3b: Zero price reverts
    function test_zeroPriceReverts() public {
        primary.setPrice(0, block.timestamp, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector));
        oracle.getLatestPrice();
    }

    /// @notice Test 4: Incomplete round (answeredInRound < roundId) reverts
    function test_incompleteRoundReverts() public {
        primary.setPrice(2000e8, block.timestamp, 5, 3); // answeredInRound(3) < roundId(5)
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.IncompleteRound.selector));
        oracle.getLatestPrice();
    }

    /// @notice Test 5: Both oracles stale reverts with BothOraclesStale
    function test_bothOraclesStaleReverts() public {
        // Both oracles stale (2 hours old)
        primary.setPrice(2000e8, block.timestamp - 7200, 1, 1);
        fallback.setPrice(2001e8, block.timestamp - 7200, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.BothOraclesStale.selector));
        oracle.getLatestPriceWithFallback();
    }

    /// @notice Test 6: Stale primary → fallback works
    function test_stalePrimaryFallsBack() public {
        // Primary stale
        primary.setPrice(2000e8, block.timestamp - 7200, 1, 1);
        // Fallback valid
        fallback.setPrice(2001e8, block.timestamp, 1, 1);

        vm.expectEmit(true, true, true, true);
        emit PriceOracle.StalePrice(address(primary), block.timestamp - 7200);
        int256 price = oracle.getLatestPriceWithFallback();
        assertEq(price, 2001e8, "Should return fallback oracle price");
    }

    /// @notice Test 7: Valid primary → no fallback needed
    function test_validPrimaryNoFallback() public view {
        int256 price = oracle.getLatestPriceWithFallback();
        assertEq(price, 2000e8, "Should return primary oracle price");
    }

    /// @notice Test 8: MAX_STALENESS is configurable
    function test_setMaxStaleness() public {
        oracle.setMaxStaleness(1800); // 30 minutes
        assertEq(oracle.MAX_STALENESS(), 1800, "Staleness should be updated");
    }

    /// @notice Test 9: Non-owner cannot set MAX_STALENESS
    function test_setMaxStalenessNotOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Not owner");
        oracle.setMaxStaleness(1800);
    }
}
