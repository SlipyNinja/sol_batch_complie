// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./19_54_IERC20.sol";
import "./11_54_IERC721.sol";

import "./6_54_ILoanCore.sol";
import "./47_54_IOriginationController.sol";
import "./48_54_IFeeController.sol";

import "./49_54_IFlashLoanRecipient.sol";

import "./50_54_ILoanCoreV2.sol";
import "./51_54_IRepaymentControllerV2.sol";

interface IMigrationBase is IFlashLoanRecipient {
    event PausedStateChanged(bool isPaused);

    function flushToken(IERC20 token, address to) external;

    function pause(bool _pause) external;
}
