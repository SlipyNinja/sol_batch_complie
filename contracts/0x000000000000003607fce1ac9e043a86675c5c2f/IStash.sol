// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OrderType} from "../helpers/Enum.sol";
import {Order} from "../helpers/Struct.sol";

interface IStash {
    function placeOrder(uint80 pricePerUnit, uint16 numberOfUnits) external payable;
    function processOrder(uint80 pricePerUnit, uint16 numberOfUnits) external;
    function availableLiquidity(address tokenAddress) external view returns (uint256);
    function wrapPunk(uint256 punkIndex) external;
    function getOrder(address paymentToken) external view returns (Order memory);
    function withdraw(address tokenAddress, uint256 amount) external;
    function owner() external view returns (address);
    function version() external view returns (uint256);
}
