// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title OwnerProxy
 * @dev OwnerProxy is a proxy contract that provides an onchain interface of
 * just the Ownable functions.
 *
 * The main purpose of this contract is to allow for deploying to
 * deterministic addresses via CREATE2, while still allowing for the owner
 * address to be updated. Normally, the owner address is set at deployment
 * time as a constructor arg, which means that the address of the contract
 * is not known until after it is deployed. This makes it difficult to
 * deploy contracts to a deterministic address.
 *
 * The OwnerProxy contract can be deployed to a preconfigured address via a
 * CREATE2 factory, after which subsequent contracts can be written to
 * refer to the OwnerProxy contract (at its preconfigured address) as
 * a way to determine the owner of the address at deployment time
 * for _subsequent_ CREATE2 deployments of _other_ contracts.
 *
 * Other contracts should be written to accept an OwnerProxy address as a
 * constructor arg, and then use that OwnerProxy's owner() as the owner
 * address for the contract being deployed.
 *
 *    ```
 *    constructor(address ownerProxy) {
 *      transferOwnership(Ownable(ownerProxy).owner());
 *    }
 *    ```
 *
 * This allows developers to mine CREATE2 addresses with static constructor
 * args input once this OwnerProxy is deployed, while still using different
 * owner addresses on different chains, (e.g. test or prod) by manipulating the
 * owner() of the OwnerProxy at deployment time of future contracts that
 * refer to it.
 *
 * This mechanism allows for developers to:
 * - deploy initization code via CREATE2 to static address (can be mined)
 * - to a developer-controlled owner address
 * - on any EVM chain
 * - now or in the future
 * - while allowing the post-deployment owner address to be updated for each
 *   deployment or chain
 *
 * so long as:
 * - OwnerProxy is deployed via CREATE2 to the same address across all chains
 * - such that it can be passed in as a deterministic constructor arg to
 *   contracts
 *
 * To ensure OwnerProxy is deployed at the same address it can either be:
 * - deployed via a CREATE2 factory with a deterministic salt
 * - deployed via the same deployer at the same nonce across all EVM chains
 *
 * The standard sequence as designed is:
 * - Determine deployer key
 * - Deploy 0age's ImmutableCreate2Factory as nonce 0 transaction
 *   (deterministic address)
 * - Deploy OwnerProxy via ImmutableCreate2Factory::safeCreate2 with
 *   deterministic salt S
 * - Deploy contract(s) with constructor arg of OwnerProxy address
 * - In contract constructor, transfer ownership to OwnerProxy::owner()
 */
contract OwnerProxy is Ownable {
  error NotMasterOwner();
  address public immutable masterOwner;

  /**
   * @dev Construct the OwnerProxy.
   * @param masterOwner_ The address of the master owner.
   */
  constructor(address masterOwner_) {
    masterOwner = masterOwner_;

    // test test test test test test test test test test test junk
    // m/44'/60'/0'/0/0
    transferOwnership(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
  }

  /**
   * @dev Modifier to ensure that only the master owner can call a function.
   */
  modifier onlyMasterOwner() {
    if (msg.sender != masterOwner) revert NotMasterOwner();
    _;
  }

  /**
   * @dev Transfer ownership to the master owner.
   */
  function takeOwnership() external onlyMasterOwner {
    _transferOwnership(masterOwner);
  }
}
