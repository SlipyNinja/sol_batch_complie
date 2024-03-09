// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import "./24_29_IRoles.sol";
import "./07_29_IProxyCall.sol";

interface ICollectionFactory {
  function rolesContract() external returns (IRoles);

  function proxyCallContract() external returns (IProxyCall);
}