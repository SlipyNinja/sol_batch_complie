// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title Treasury
 * @dev The Treasury contract is a contract that holds funds for the protocol.
 */
abstract contract Treasury is Ownable {
  event TreasuryWithdrawal(address indexed to, uint amount);

  /**
   * @notice Withdraw funds from the contract.
   * @param amount The amount to withdraw.
   * @dev Only the owner can withdraw funds.
   */
  function withdraw(uint amount) public onlyOwner {
    require(amount <= address(this).balance, 'Insufficient balance');
    payable(msg.sender).transfer(amount);
    emit TreasuryWithdrawal(msg.sender, amount);
  }
}
