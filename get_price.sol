// SPDX-License-Identifier: MIT

// Buid arb sepolia
pragma solidity ^0.8.30;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceConsumer {
    AggregatorV3Interface internal priceFeedBTC;
    AggregatorV3Interface internal priceFeedETH;
    AggregatorV3Interface internal priceFeedBNB;

    constructor() {
        // Ethereum Mainnet Price Feed addresses (checksummed)
        priceFeedBTC = AggregatorV3Interface(
            0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69
        );
        priceFeedETH = AggregatorV3Interface(
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        );

        priceFeedBNB = AggregatorV3Interface(
            0x53ab995fBb01C617aa1256698aD55b417168bfF9
        );
    }

    function getBTCPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeedBTC.latestRoundData();
        return price;
    }

    function getETHPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeedETH.latestRoundData();
        return price;
    }

    function getBNBPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeedBNB.latestRoundData();
        return price;
    }
}
