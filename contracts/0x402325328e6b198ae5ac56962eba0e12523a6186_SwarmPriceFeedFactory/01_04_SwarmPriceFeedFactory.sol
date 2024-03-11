//SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import "./02_04_Ownable.sol";

import "./04_04_SwarmPriceFeed.sol";

contract SwarmPriceFeedFactory is Ownable {
    event PriceFeedDeployed(address priceFeedAddress);

    function deployPriceFeed(
        string memory _description,
        uint256 _initialPrice,
        uint8 _decimals
    ) external onlyOwner returns (address) {
        SwarmPriceFeed swarmPriceFeed = new SwarmPriceFeed(_description, _initialPrice, block.timestamp, _decimals);

        swarmPriceFeed.transferOwnership(_msgSender());

        emit PriceFeedDeployed(address(swarmPriceFeed));

        return address(swarmPriceFeed);
    }
}