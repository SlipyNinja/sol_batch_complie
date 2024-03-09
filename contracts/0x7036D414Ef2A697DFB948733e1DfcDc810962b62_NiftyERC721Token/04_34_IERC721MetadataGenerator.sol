// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./22_34_IERC165.sol";

interface IERC721MetadataGenerator is IERC165 {
    function contractMetadata() external view returns (string memory);
    function tokenMetadata(uint256 tokenId, uint256 niftyType, bytes calldata data) external view returns (string memory);
}