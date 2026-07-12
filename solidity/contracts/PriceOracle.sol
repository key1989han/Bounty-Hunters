// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract PriceOracle {
    AggregatorV3Interface public primaryFeed;
    AggregatorV3Interface public fallbackFeed;
    address public owner;
    uint256 public MAX_STALENESS = 3600;

    event PriceQueried(int256 price, uint256 timestamp);
    event StalePrice(uint256 lastUpdate, uint256 currentTime);
    event FallbackOracleUsed(address fallbackAddress);

    constructor(address _primaryFeed, address _fallbackFeed) {
        primaryFeed = AggregatorV3Interface(_primaryFeed);
        fallbackFeed = AggregatorV3Interface(_fallbackFeed);
        owner = msg.sender;
    }

    /**
     * @notice Get the latest price with staleness check and fallback
     * @return price The validated price from Chainlink
     */
    function getLatestPrice() external view returns (int256) {
        // Try primary oracle first
        (bool success, int256 price) = _getPriceFromFeed(primaryFeed);
        
        if (success) {
            emit PriceQueried(price, block.timestamp);
            return price;
        }

        // Primary failed - emit stale price event and try fallback
        (uint80 , , , uint256 updatedAt, ) = primaryFeed.latestRoundData();
        emit StalePrice(updatedAt, block.timestamp);

        // Try fallback oracle
        (bool fallbackSuccess, int256 fallbackPrice) = _getPriceFromFeed(fallbackFeed);
        
        if (fallbackSuccess) {
            emit FallbackOracleUsed(address(fallbackFeed));
            emit PriceQueried(fallbackPrice, block.timestamp);
            return fallbackPrice;
        }

        // Both oracles failed - revert
        revert("Both oracles returned stale/invalid data");
    }

    /**
     * @notice Internal function to validate and return price from a feed
     * @param feed The Chainlink feed to query
     * @return success Whether the price is valid
     * @return price The validated price
     */
    function _getPriceFromFeed(AggregatorV3Interface feed) internal view returns (bool success, int256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Check 1: Round completeness - ensure we have the full answer
        if (answeredInRound < roundId) {
            return (false, 0);
        }

        // Check 2: Price must be positive
        if (answer <= 0) {
            return (false, 0);
        }

        // Check 3: Staleness check - price must be recent
        if (block.timestamp - updatedAt >= MAX_STALENESS) {
            return (false, 0);
        }

        return (true, answer);
    }

    function getDecimals() external view returns (uint8) {
        return primaryFeed.decimals();
    }

    /**
     * @notice Update maximum staleness threshold
     * @param _maxStaleness New staleness threshold in seconds
     */
    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "Not owner");
        require(_maxStaleness > 0, "Staleness must be positive");
        MAX_STALENESS = _maxStaleness;
    }

    /**
     * @notice Update fallback oracle address
     * @param _fallbackFeed New fallback oracle address
     */
    function setFallbackFeed(address _fallbackFeed) external {
        require(msg.sender == owner, "Not owner");
        fallbackFeed = AggregatorV3Interface(_fallbackFeed);
    }
}
