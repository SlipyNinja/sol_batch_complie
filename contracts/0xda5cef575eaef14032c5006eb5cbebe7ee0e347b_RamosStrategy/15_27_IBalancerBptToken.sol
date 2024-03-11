pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Temple (interfaces/external/balancer/IBalancerBptToken.sol)

import { IERC20 } from "./04_27_IERC20.sol";

interface IBalancerBptToken is IERC20 {
    function getActualSupply() external view returns (uint256);
}