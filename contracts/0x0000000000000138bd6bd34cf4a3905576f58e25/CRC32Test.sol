// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import '../CRC32.sol';

// This contract is used to test the CRC32 library
contract CRC32Test {
  function crc32(bytes memory data) public pure returns (uint32) {
    return CRC32.crc32(data, 0, data.length);
  }
}
