// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.12;

/**
 * @title Declares the interface for initializing an NFTCollection contract.
 * @author batu-inal & HardlyDifficult
 */
interface INFTCollectionInitializer {
  function initialize(address payable _creator, string memory _name, string memory _symbol) external;
}
