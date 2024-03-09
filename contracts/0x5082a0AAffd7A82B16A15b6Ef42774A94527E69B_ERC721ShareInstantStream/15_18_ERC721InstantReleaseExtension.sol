// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import "./02_18_Initializable.sol";
import "./01_18_Ownable.sol";
import "./11_18_ERC165Storage.sol";

import "./07_18_Address.sol";
import "./09_18_Counters.sol";
import "./03_18_ReentrancyGuard.sol";
import "./04_18_IERC20.sol";
import "./05_18_IERC721.sol";

import "./14_18_ERC721MultiTokenStream.sol";

interface IERC721InstantReleaseExtension {
    function hasERC721InstantReleaseExtension() external view returns (bool);
}

abstract contract ERC721InstantReleaseExtension is
    IERC721InstantReleaseExtension,
    Initializable,
    Ownable,
    ERC165Storage,
    ERC721MultiTokenStream
{
    /* INIT */

    function __ERC721InstantReleaseExtension_init() internal onlyInitializing {
        __ERC721InstantReleaseExtension_init_unchained();
    }

    function __ERC721InstantReleaseExtension_init_unchained()
        internal
        onlyInitializing
    {
        _registerInterface(type(IERC721InstantReleaseExtension).interfaceId);
    }

    /* PUBLIC */

    function hasERC721InstantReleaseExtension() external pure returns (bool) {
        return true;
    }

    /* INTERNAL */

    function _totalStreamReleasedAmount(
        uint256 streamTotalSupply_,
        uint256 ticketTokenId_,
        address claimToken_
    ) internal pure override returns (uint256) {
        ticketTokenId_;
        claimToken_;

        return streamTotalSupply_;
    }
}