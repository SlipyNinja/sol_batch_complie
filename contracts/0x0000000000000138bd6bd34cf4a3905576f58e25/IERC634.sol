// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IERC634: Text Data Interface
 * @dev This is the same as EIP-634 with different variable names
 * - rename node -> dna
 * - +calldata for key in text()
 * - +external for text()
 * - +memory for return value of text()
 */
interface IERC634 {
  /**
   * @notice Returns the text data associated with a DNA
   * @param dna A DNA to lookup text data for
   * @param key A key to lookup text data for
   * @return text The text data
   */
  function text(bytes32 dna, string calldata key) external view returns (string memory text);
}
