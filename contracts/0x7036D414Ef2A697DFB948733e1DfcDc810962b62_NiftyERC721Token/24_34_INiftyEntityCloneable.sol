// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./22_34_IERC165.sol";

interface INiftyEntityCloneable is IERC165 {
    function initializeNiftyEntity(address niftyRegistryContract_) external;
}