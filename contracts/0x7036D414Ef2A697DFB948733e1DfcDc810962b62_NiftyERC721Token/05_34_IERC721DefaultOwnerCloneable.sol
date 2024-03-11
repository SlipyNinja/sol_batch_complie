// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./22_34_IERC165.sol";

interface IERC721DefaultOwnerCloneable is IERC165 {
    function initializeDefaultOwner(address defaultOwner_) external;    
}