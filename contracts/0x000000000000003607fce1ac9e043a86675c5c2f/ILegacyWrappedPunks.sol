// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ILegacyWrappedPunks {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function proxyInfo(address) external view returns (address);
    function registerProxy() external;
    function burn(uint256 punkId) external;
    function mint(uint256 punkId) external;
    function approve(address to, uint256 punkId) external;
    function ownerOf(uint256 punkId) external view returns (address);
}
