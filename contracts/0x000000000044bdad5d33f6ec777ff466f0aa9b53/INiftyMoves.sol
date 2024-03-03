// SPDX-License-Identifier: MIT

/**
 *
 * @title NiftyMoves.sol. Convenient and gas efficient protocol for sending multiple
 * ERC721s from multiple contracts to multiple recipients, or the burn address.
 *
 * v4.0.0
 *
 * @author niftymoves https://niftymoves.io/
 * @author omnus      https://omn.us/
 *
 */

pragma solidity 0.8.21;

interface INiftyMoves {
  // Struct object that represents a single transfer request.
  // This has one 'to' address with 1 to n collections and 1 to n
  // tokens / quantities within each collection:
  struct Transfer {
    address toAddress;
    address[] contractAddresses;
    uint256[][] tokenIDs;
  }

  // Struct for discount parameters:
  struct DiscountParameters {
    address contractOrPayee;
    bytes12 referralID;
    uint256 tokenID1155;
    uint256 minimumBalance;
    uint256 discountBasisPoints;
    uint256 referrerBasisPoints;
  }

  // Struct for trusted provider bonuses
  struct TrustedProviderBonuses {
    address collection;
    uint256 transferCount;
  }

  event TransferFeeUpdated(uint256 newEthFee);
  event TreasuryUpdated(address newTreasury);
  event WETHAddressUpdated(address newWETH);
  event DiscountRootUpdated(bytes32 newDiscountRoot);
  event ENSReverseRegistrarUpdated(address newENSReverseRegistrar);
  event ENSNameSet(string name, bytes32 reverseRecordHash);

  /**
   *
   * @dev enableService: enable niftymoves (onlyOwner)
   *
   */
  function enableService() external;

  /**
   *
   * @dev disableService: disable niftymoves (onlyOwner)
   *
   */
  function disableService() external;

  /**
   *
   * @dev setENSReverseRegistrar: set the ENS register address (onlyOwner)
   *
   * @param ensRegistrar_: ENS Reverse Registrar address
   *
   */
  function setENSReverseRegistrar(address ensRegistrar_) external;

  /**
   *
   * @dev setENSName: used to set reverse record so interactions with this contract
   * are easy to identify (onlyOwner)
   *
   * @param ensName_: string ENS name
   *
   */
  function setENSName(string memory ensName_) external;

  /**
   *
   * @dev setTransferFee: set a fee per transfer (onlyOwner)
   *
   * @param transferFee_: the new fee
   *
   */
  function setTransferFee(uint88 transferFee_) external;

  /**
   *
   * @dev setWETH: set the WETH address for this chain (onlyOwner)
   *
   * @param wethAddress_: the new WETH address
   *
   */
  function setWETH(address wethAddress_) external;

  /**
   *
   * @dev setDiscountRoot: set the discount merkle root (onlyOwner)
   *
   * @param discountRoot_: the new root
   *
   */
  function setDiscountRoot(bytes32 discountRoot_) external;

  /**
   *
   * @dev setTreasury: set a new treasury address (onlyOwner)
   *
   * @param treasury_: the new treasury address
   *
   */
  function setTreasury(address treasury_) external;

  /**
   *
   * @dev withdrawETH: withdraw to the treasury address (onlyOwner)
   *
   * @param amount_: amount to withdraw
   *
   */
  function withdrawETH(uint256 amount_) external;

  /**
   *
   * @dev withdrawERC721: Retrieve ERC721s, likely only the ENS associated
   * with this contract (onlyOwner)
   *
   * @param erc721Address_: The token contract for the withdrawal
   * @param tokenIDs_: the list of tokenIDs for the withdrawal
   *
   */
  function withdrawERC721(
    address erc721Address_,
    uint256[] memory tokenIDs_
  ) external;

  /**
   *
   * @dev niftyMove: perform multiple ERC-721 transfers in a single transaction
   *
   * niftyMove is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      **WITHOUT**
   *    Trusted provider bonus    **WITHOUT**
   *
   * @param transfers_: struct object containing an array of transfers
   * @param transferCount_: count of transfers
   * @param standardTransferGas_: gas cost of standard transfer
   *
   */
  function niftyMove(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_
  ) external payable;

  /**
   *
   * @dev niftyMove: perform multiple ERC-721 transfers in a single transaction
   *
   * niftyMove is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      ** WITH  **
   *    Trusted provider bonus    **WITHOUT**
   *
   * @param transfers_: struct object containing an array of transfers
   * @param transferCount_: count of transfers
   * @param standardTransferGas_: gas cost of standard transfer
   * @param gasLimit_: gas limit for ETH transfers
   * @param discountDetails_: details of the discount being claimed
   * @param proof_: proof for validating discount / referral details
   *
   */
  function niftyMove(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_,
    uint256 gasLimit_,
    DiscountParameters calldata discountDetails_,
    bytes32[] calldata proof_
  ) external payable;

  /**
   *
   * @dev niftyMove: perform multiple ERC-721 transfers in a single transaction
   *
   * niftyMove is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      ** WITH  **
   *    Trusted provider bonus    ** WITH  **
   *
   * @param transfers_: struct object containing an array of transfers
   * @param transferCount_: count of transfers
   * @param standardTransferGas_: gas cost of standard transfer
   * @param gasLimit_: gas limit for ETH transfers
   * @param discountDetails_: details of the discount being claimed
   * @param proof_: proof for validating discount / referral details
   * @param trustedProviderCollectionCount_: Number of trusted provider collections
   *
   */
  function niftyMove(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_,
    uint256 gasLimit_,
    DiscountParameters calldata discountDetails_,
    bytes32[] calldata proof_,
    uint256 trustedProviderCollectionCount_
  ) external payable;

  /**
   *
   * @dev niftyBurn: function to perform multiple burns
   *
   * niftyBurn is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      ** WITHOUT**
   *    Trusted provider bonus    ** WITHOUT**
   *
   * @param transfers_: struct object containing an array of burns
   * @param transferCount_: count of burns
   * @param standardTransferGas_: gas cost of standard burns
   *
   */
  function niftyBurn(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_
  ) external payable;

  /**
   *
   * @dev niftyBurn: function to perform multiple burns
   *
   * niftyBurn is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      ** WITH  **
   *    Trusted provider bonus    ** WITHOUT**
   *
   * @param transfers_: struct object containing an array of burns
   * @param transferCount_: count of burns
   * @param standardTransferGas_: gas cost of standard burns
   * @param gasLimit_: gas limit for ETH transfers
   * @param discountDetails_: details of the discount being claimed
   * @param proof_: proof for validating discount / referral details
   *
   */
  function niftyBurn(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_,
    uint256 gasLimit_,
    DiscountParameters calldata discountDetails_,
    bytes32[] calldata proof_
  ) external payable;

  /**
   *
   * @dev niftyBurn: function to perform multiple burns
   *
   * niftyBurn is an overloaded function providing the following implementations:
   * 1) Move WITHOUT a discount or referral and WITHOUT trusted provider bonus(es)
   * 2) Move WITH a discount or referral and WITHOUT trusted provider bonus(es)
   * 3) Move WITH a discount or referral and WITH trusted provider bonus(es)
   *
   * Overloading in this way allows us to avoid IF statements in the code, keeping
   * gas costs to a minimum. It does so at the cost of reduced code reuse.
   *
   * This instance of the overloaded method is for the following:
   *
   *    Discount or Referral      ** WITH  **
   *    Trusted provider bonus    ** WITH  **
   *
   * @param transfers_: struct object containing an array of burns
   * @param transferCount_: count of burns
   * @param standardTransferGas_: gas cost of standard burns
   * @param gasLimit_: gas limit for ETH transfers
   * @param discountDetails_: details of the discount being claimed
   * @param proof_: proof for validating discount / referral details
   * @param trustedProviderCollectionCount_: Number of trusted provider collections
   *
   */
  function niftyBurn(
    Transfer[] calldata transfers_,
    uint256 transferCount_,
    uint256 standardTransferGas_,
    uint256 gasLimit_,
    DiscountParameters calldata discountDetails_,
    bytes32[] calldata proof_,
    uint256 trustedProviderCollectionCount_
  ) external payable;

  /**
   *
   * @dev rootIsValid: check the passed details against the root
   *
   * @param proof_: the proof used to check passed details
   * @param discountDetails_: struct object for the claimed discount
   *
   * @return valid_ :  if this set of data is valid (or not)
   *
   */
  function rootIsValid(
    bytes32[] calldata proof_,
    DiscountParameters calldata discountDetails_
  ) external view returns (bool valid_);
}
