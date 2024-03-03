// SPDX-License-Identifier: MIT
// Creator: Exo Digital Labs

pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/// @notice Refundable ERC-721 tokens
/// @dev    The ERC-165 identifier of this interface is `0xe97f3c83`
interface ERC721Refund is IERC165 {
    /// @notice           Emitted when a token is refunded
    /// @dev              Emitted by `refund`
    /// @param  _from     The account whose assets are refunded
    /// @param  _tokenId  The `tokenId` that was refunded
    event Refund(address indexed _from, uint256 indexed _tokenId);

    /// @notice           Emitted when a token is refunded
    /// @dev              Emitted by `refundFrom`
    /// @param  _sender   The account that sent the refund
    /// @param  _from     The account whose assets are refunded
    /// @param  _tokenId  The `tokenId` that was refunded
    event RefundFrom(
        address indexed _sender,
        address indexed _from,
        uint256 indexed _tokenId
    );

    /// @notice         As long as the refund is active for the given `tokenId`, refunds the user
    /// @dev            Make sure to check that the user has the token, and be aware of potential re-entrancy vectors
    /// @param  tokenId The `tokenId` to refund
    function refund(uint256 tokenId) external;

    /// @notice         As long as the refund is active and the sender has sufficient approval, refund the token and send the ether to the sender
    /// @dev            Make sure to check that the user has the token, and be aware of potential re-entrancy vectors
    ///                 The ether goes to msg.sender.
    /// @param  from    The user from which to refund the token
    /// @param  tokenId The `tokenId` to refund
    function refundFrom(address from, uint256 tokenId) external;

    /// @notice         Gets the refund price of the specific `tokenId`
    /// @param  tokenId The `tokenId` to query
    /// @return _wei    The amount of ether (in wei) that would be refunded
    function refundOf(uint256 tokenId) external view returns (uint256 _wei);

    /// @notice         Gets the first block for which the refund is not active for a given `tokenId`
    /// @param  tokenId The `tokenId` to query
    /// @return block   The first block where token cannot be refunded
    function refundDeadlineOf(
        uint256 tokenId
    ) external view returns (uint256 block);
}
