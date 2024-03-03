// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface ICryptoPunks {
    function punksOfferedForSale(uint256)
        external
        view
        returns (bool isForSale, uint256 punkIndex, address seller, uint256 minValue, address onlySellTo);
    function buyPunk(uint256) external payable;
    function transferPunk(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
    function punkIndexToAddress(uint256) external view returns (address);
    function pendingWithdrawals(address) external view returns (uint256);
    function offerPunkForSaleToAddress(uint256, uint256, address) external;
    function getPunk(uint256 punkId) external;
}
