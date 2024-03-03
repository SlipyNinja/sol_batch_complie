// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title FuseGuard
 * @dev A contract that manages fuses.
 */
abstract contract FuseGuard {
  /// @dev Revert error when operation is blocked by burned fuse.
  error OperationBlockedByBurnedFuse();
}
