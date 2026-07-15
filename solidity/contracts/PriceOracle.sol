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
    event StalePrice(address indexed oracle, uint256 lastUpdate);

    error InvalidPrice();
    error IncompleteRound();
    error StalePriceError(uint256 lastUpdate);
    error BothOraclesStale();

    constructor(address _primaryFeed, address _fallbackFeed) {
        primaryFeed = AggregatorV3Interface(_primaryFeed);
        fallbackFeed = AggregatorV3Interface(_fallbackFeed);
        owner = msg.sender;
    }

    function getLatestPrice() external view returns (int256) {
        return _getPriceFromFeed(primaryFeed);
    }

    function getLatestPriceWithFallback() external returns (int256) {
        (bool success, int256 price) = _tryGetPrice(primaryFeed);
        if (success) {
            return price;
        }

        (, , , uint256 primaryUpdatedAt, ) = primaryFeed.latestRoundData();
        emit StalePrice(address(primaryFeed), primaryUpdatedAt);

        (bool fbSuccess, int256 fbPrice) = _tryGetPrice(fallbackFeed);
        if (fbSuccess) {
            return fbPrice;
        }

        revert BothOraclesStale();
    }

    function _getPriceFromFeed(AggregatorV3Interface feed) internal view returns (int256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answeredInRound < roundId) {
            revert IncompleteRound();
        }

        if (price <= 0) {
            revert InvalidPrice();
        }

        if (block.timestamp - updatedAt >= MAX_STALENESS) {
            revert StalePriceError(updatedAt);
        }

        return price;
    }

    function _tryGetPrice(AggregatorV3Interface feed) internal view returns (bool success, int256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answeredInRound < roundId) {
            return (false, 0);
        }

        if (answer <= 0) {
            return (false, 0);
        }

        if (block.timestamp - updatedAt >= MAX_STALENESS) {
            return (false, 0);
        }

        return (true, answer);
    }

    function getDecimals() external view returns (uint8) {
        return primaryFeed.decimals();
    }

    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "Not owner");
        MAX_STALENESS = _maxStaleness;
    }
}
