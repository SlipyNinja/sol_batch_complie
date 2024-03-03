// SPDX-License-Identifier: BUSL-1.1

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

import {IENSReverseRegistrar} from "./ENS/IENSReverseRegistrar.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721, ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INiftyMoves} from "./INiftyMoves.sol";
import {IWETH} from "./WETH/IWETH.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NiftyMoves is INiftyMoves, IERC721Receiver, Ownable {
  using SafeERC20 for IERC20;

  uint256 private constant DENOMINATOR_BASIS_POINTS = 10000;
  uint256 private constant BONUS_RATE_IN_BASIS_POINTS = 5000;

  // ETH fee for transfers, if any:
  uint88 public transferFee;

  // Boolean to control service availability:
  bool public enabled = true;

  // WETH:
  IWETH public wethContract;

  // Treasury to receive any ETH fees, if any:
  address public treasury;

  // Address of the ENS reverse registrar to allow assignment of an ENS
  // name to this contract:
  IENSReverseRegistrar public ensReverseRegistrar;

  // The merkleroot for referralls / discounts
  bytes32 public discountRoot;

  // Version codename:
  string public version = "Dugong";

  /**
   *
   * @dev constructor
   *
   */
  constructor() {
    // Initialise the treasury and owner to the deployer:
    treasury = tx.origin;
    _transferOwnership(tx.origin);
  }

  /**
   * @dev whenEnabled: Modifier to make a function callable only when the contract is enabled.
   *
   * Requirements:
   *
   * - The contract must be enabled.
   */
  modifier whenEnabled() {
    require(enabled, "niftymoves: not currently enabled");
    _;
  }

  /**
   *
   * @dev enableService: enable niftymoves (onlyOwner)
   *
   */
  function enableService() external onlyOwner {
    enabled = true;
  }

  /**
   *
   * @dev disableService: disable niftymoves (onlyOwner)
   *
   */
  function disableService() external onlyOwner {
    enabled = false;
  }

  /**
   *
   * @dev setENSReverseRegistrar: set the ENS register address (onlyOwner)
   *
   * @param ensRegistrar_: ENS Reverse Registrar address
   *
   */
  function setENSReverseRegistrar(address ensRegistrar_) external onlyOwner {
    ensReverseRegistrar = IENSReverseRegistrar(ensRegistrar_);
    emit ENSReverseRegistrarUpdated(ensRegistrar_);
  }

  /**
   *
   * @dev setENSName: used to set reverse record so interactions with this contract
   * are easy to identify (onlyOwner)
   *
   * @param ensName_: string ENS name
   *
   */
  function setENSName(string memory ensName_) external onlyOwner {
    bytes32 reverseRecordHash = ensReverseRegistrar.setName(ensName_);
    emit ENSNameSet(ensName_, reverseRecordHash);
  }

  /**
   *
   * @dev setTransferFee: set a fee per transfer (onlyOwner)
   *
   * @param transferFee_: the new fee
   *
   */
  function setTransferFee(uint88 transferFee_) external onlyOwner {
    transferFee = transferFee_;
    emit TransferFeeUpdated(transferFee_);
  }

  /**
   *
   * @dev setWETH: set the WETH address for this chain (onlyOwner)
   *
   * @param wethAddress_: the new WETH address
   *
   */
  function setWETH(address wethAddress_) external onlyOwner {
    wethContract = IWETH(wethAddress_);
    emit WETHAddressUpdated(wethAddress_);
  }

  /**
   *
   * @dev setDiscountRoot: set the discount merkle root (onlyOwner)
   *
   * @param discountRoot_: the new root
   *
   */
  function setDiscountRoot(bytes32 discountRoot_) external onlyOwner {
    discountRoot = discountRoot_;
    emit DiscountRootUpdated(discountRoot_);
  }

  /**
   *
   * @dev setTreasury: set a new treasury address (onlyOwner)
   *
   * @param treasury_: the new treasury address
   *
   */
  function setTreasury(address treasury_) external onlyOwner {
    require(treasury_ != address(0), "niftymoves: cannot set to zero address");
    treasury = treasury_;
    emit TreasuryUpdated(treasury_);
  }

  /**
   *
   * @dev withdrawETH: withdraw to the treasury address (onlyOwner)
   *
   * @param amount_: amount to withdraw
   *
   */
  function withdrawETH(uint256 amount_) external onlyOwner {
    (bool success, ) = treasury.call{value: amount_}("");
    require(success, "niftymoves: fransfer failed");
  }

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
  ) external onlyOwner {
    for (uint256 i = 0; i < tokenIDs_.length; ) {
      IERC721(erc721Address_).transferFrom(
        address(this),
        owner(),
        tokenIDs_[i]
      );
      unchecked {
        ++i;
      }
    }
  }

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
  ) external payable whenEnabled {
    require(
      msg.value == transferFee * transferCount_,
      "niftymoves: incorrect payment"
    );

    // Perform transfers:
    uint256 transferCount = _performMoves(
      _msgSender(),
      transfers_,
      standardTransferGas_
    );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );
  }

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
  ) external payable whenEnabled {
    // Perform fee processing:
    _processFees(
      msg.value,
      transferCount_,
      discountDetails_,
      gasLimit_,
      proof_
    );

    // Perform transfers:
    uint256 transferCount = _performMoves(
      _msgSender(),
      transfers_,
      standardTransferGas_
    );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );
  }

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
  ) external payable whenEnabled {
    // Perform fee processing:
    uint256 referrerPayment = _processFees(
      msg.value,
      transferCount_,
      discountDetails_,
      gasLimit_,
      proof_
    );

    // Perform transfers:
    (
      uint256 transferCount,
      TrustedProviderBonuses[] memory bonuses
    ) = _performMovesAsTrustedProvider(
        _msgSender(),
        transfers_,
        standardTransferGas_,
        trustedProviderCollectionCount_
      );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );

    // Handle trusted provider bonuses, if any:
    if (bonuses.length > 0) {
      _remitBonuses(
        bonuses,
        (((msg.value - referrerPayment) / transferCount_) *
          BONUS_RATE_IN_BASIS_POINTS) / DENOMINATOR_BASIS_POINTS,
        gasLimit_
      );
    }
  }

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
  ) external payable whenEnabled {
    require(
      msg.value == transferFee * transferCount_,
      "niftymoves: incorrect payment"
    );

    // Perform burns:
    uint256 transferCount = _performBurns(
      _msgSender(),
      transfers_,
      standardTransferGas_
    );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );
  }

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
  ) external payable whenEnabled {
    // Perform fee processing:
    _processFees(
      msg.value,
      transferCount_,
      discountDetails_,
      gasLimit_,
      proof_
    );

    // Perform burns:
    uint256 transferCount = _performBurns(
      _msgSender(),
      transfers_,
      standardTransferGas_
    );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );
  }

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
  ) external payable whenEnabled {
    // Perform fee processing:
    uint256 referrerPayment = _processFees(
      msg.value,
      transferCount_,
      discountDetails_,
      gasLimit_,
      proof_
    );

    // Perform burns:
    (
      uint256 transferCount,
      TrustedProviderBonuses[] memory bonuses
    ) = _performBurnsAsTrustedProvider(
        _msgSender(),
        transfers_,
        standardTransferGas_,
        trustedProviderCollectionCount_
      );

    // Validate transfer count received:
    require(
      (transferCount_ == transferCount),
      "niftymoves: transfer count mismatch"
    );

    // Handle trusted provider bonuses, if any:
    if (bonuses.length > 0) {
      _remitBonuses(
        bonuses,
        (((msg.value - referrerPayment) / transferCount_) *
          BONUS_RATE_IN_BASIS_POINTS) / DENOMINATOR_BASIS_POINTS,
        gasLimit_
      );
    }
  }

  /**
   *
   * @dev _remitBonuses: send bonus payments to collections that have added
   * niftymoves as a trusted provider.
   *
   */
  function _remitBonuses(
    TrustedProviderBonuses[] memory bonuses_,
    uint256 bonusFeePerTokenTransfered_,
    uint256 gasLimit_
  ) internal returns (bool) {
    uint256 payment;
    bool success;
    for (uint256 i = 0; i < bonuses_.length; ) {
      payment = bonusFeePerTokenTransfered_ * bonuses_[i].transferCount;

      if (payment > 0) {
        // If gas limit is zero or greater than gas left, use the remaining gas.
        uint256 gas = (gasLimit_ == 0 || gasLimit_ > gasleft())
          ? gasleft()
          : gasLimit_;

        (success, ) = bonuses_[i].collection.call{value: payment, gas: gas}("");
      }

      unchecked {
        i++;
      }
    }
    return (success);
  }

  /**
   *
   * @dev _isTrustedProvider: form a random address for checking trusted provider implementation
   *
   * @return isTrustedProvider_ : this is / isn't a trusted provider
   *
   */
  function _isTrustedProvider(
    address contract_
  ) internal view returns (bool isTrustedProvider_) {
    return (
      IERC721(contract_).isApprovedForAll(
        address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp))))),
        address(this)
      )
    );
  }

  /**
   *
   * @dev _performMoves: move items on-chain.
   *
   * @param sender_: the calling address for this transaction
   * @param transfers_: the struct object containing the transfers
   *
   * @return transferCount_ : a count of the number of transfer transactions
   *
   */
  function _performMoves(
    address sender_,
    Transfer[] calldata transfers_,
    uint256
  ) internal returns (uint256 transferCount_) {
    // Iterate through the list of transfer objects. There is one transfer
    // object per 'to' address:
    for (uint256 transfer = 0; transfer < transfers_.length; ) {
      // Check that the addresses and tokenId lists for this transfer match length:
      require(
        transfers_[transfer].contractAddresses.length ==
          transfers_[transfer].tokenIDs.length,
        "niftymoves: length mismatch, contracts and tokens lists"
      );

      // Iterate through the list of collections for this "to" address:
      for (
        uint256 collection = 0;
        collection < transfers_[transfer].contractAddresses.length;

      ) {
        uint256 item;
        for (
          item = 0;
          item < transfers_[transfer].tokenIDs[collection].length;

        ) {
          _efficient721Transfer(
            sender_,
            transfers_[transfer].toAddress,
            transfers_[transfer].contractAddresses[collection],
            transfers_[transfer].tokenIDs[collection][item]
          );
          unchecked {
            item++;
          }
        }
        unchecked {
          transferCount_ += item;
          collection++;
        }
      }
      unchecked {
        transfer++;
      }
    }

    return (transferCount_);
  }

  /**
   *
   * @dev _performMovesAsTrustedProvider: move items on-chain.
   *
   * @param sender_: the calling address for this transaction
   * @param transfers_: the struct object containing the transfers
   * @param trustedProviderCollectionCount_: A count of collections in this
   * niftymove IF the UI has identified that one or more collections has
   * niftymoves as a trusted provider, and therefore qualifies for the bonus.
   *
   * @return transferCount_ : a count of the number of transfer transactions
   * @return bonuses_ : an array of bonus data structs
   *
   */
  function _performMovesAsTrustedProvider(
    address sender_,
    Transfer[] calldata transfers_,
    uint256,
    uint256 trustedProviderCollectionCount_
  )
    internal
    returns (uint256 transferCount_, TrustedProviderBonuses[] memory bonuses_)
  {
    bonuses_ = new TrustedProviderBonuses[](trustedProviderCollectionCount_);
    uint256 bonusCount;

    // Iterate through the list of transfer objects. There is one transfer
    // object per 'to' address:
    for (uint256 transfer = 0; transfer < transfers_.length; ) {
      // Check that the addresses and tokenId lists for this transfer match length:
      require(
        transfers_[transfer].contractAddresses.length ==
          transfers_[transfer].tokenIDs.length,
        "niftymoves: length mismatch, contracts and tokens lists"
      );

      // Iterate through the list of collections for this "to" address:
      for (
        uint256 collection = 0;
        collection < transfers_[transfer].contractAddresses.length;

      ) {
        uint256 item;
        for (
          item = 0;
          item < transfers_[transfer].tokenIDs[collection].length;

        ) {
          _efficient721Transfer(
            sender_,
            transfers_[transfer].toAddress,
            transfers_[transfer].contractAddresses[collection],
            transfers_[transfer].tokenIDs[collection][item]
          );
          unchecked {
            item++;
          }
        }
        unchecked {
          // See if we have a collection wide discount through niftymoves
          // being included as a trusted service provider:
          if (
            trustedProviderCollectionCount_ != 0 &&
            _isTrustedProvider(
              transfers_[transfer].contractAddresses[collection]
            )
          ) {
            // Collection has loaded niftymoves as a trusted provider. Record bonuses for distribution:
            bonuses_[bonusCount] = TrustedProviderBonuses(
              transfers_[transfer].contractAddresses[collection],
              item
            );
            bonusCount++;
          }
          transferCount_ += item;
          collection++;
        }
      }
      unchecked {
        transfer++;
      }
    }

    if (bonusCount != 0) {
      // Trim the list if is has more entries than we needed:
      if (trustedProviderCollectionCount_ > bonusCount) {
        assembly {
          let decrease := sub(trustedProviderCollectionCount_, bonusCount)
          mstore(bonuses_, sub(mload(bonuses_), decrease))
        }
      }
    }

    return (transferCount_, bonuses_);
  }

  /**
   *
   * @dev _efficient721Transfer: transfer items
   *
   * @param from_: the calling address for this transaction
   * @param to_: the address to which items are being transferred
   * @param contract_: the contract for the items being transferred
   * @param tokenId_: the tokenId being transferred
   *
   */
  function _efficient721Transfer(
    address from_,
    address to_,
    address contract_,
    uint256 tokenId_
  ) internal {
    bool success;

    assembly {
      let transferFromData := add(0x20, mload(0x40))
      // 0x23b872dd is the selector of {transferFrom}.
      mstore(
        transferFromData,
        0x23b872dd00000000000000000000000000000000000000000000000000000000
      )

      mstore(add(transferFromData, 0x04), from_)
      mstore(add(transferFromData, 0x24), to_)
      mstore(add(transferFromData, 0x44), tokenId_)

      success := call(gas(), contract_, 0, transferFromData, 0x64, 0, 0)

      // This has failed. Failures are not bubbled up the call stack (for example in the case of
      // the caller not being the owner of the token). We could pass back a custom error saying
      // the transfer has failed as follows. We won't (see below), but code provided here in
      // comments for anyone wishing to see the approach.
      // 0x90b8ec18 is the selector of {TransferFailed}.
      // if iszero(success) {
      //   mstore(
      //     0x00,
      //     0x1c43b97600000000000000000000000000000000000000000000000000000000
      //   )
      //   // Store the tokenContract address at the beginning of the error data
      //   mstore(0x04, contract_)
      //   // Store the tokenId immediately after the tokenContract address
      //   mstore(0x24, tokenId_)
      //   revert(0x00, 0x44)
      // }
    }
    if (!success) {
      // Contract call to return reason up call stack. This will cost a bit more gas
      // than handling the error in assembly and returning an error (e.g. TransferFailed)
      // directly from this contract. But that would remove all detail from the returned error
      // message, making it far harder for the end user to understand the reason for the
      // failure. Note in all cases the app should apply pre-call validation to avoid such
      // errors costing *any* gas.
      IERC721(contract_).transferFrom(from_, to_, tokenId_);
    }
  }

  /**
   *
   * @dev _performBurns: burn items on-chain.
   *
   * @param sender_: the calling address for this transaction
   * @param transfers_: the struct object containing the transfers
   *
   * @return transferCount_ : a count of the number of transfer transactions
   *
   */
  function _performBurns(
    address sender_,
    Transfer[] calldata transfers_,
    uint256
  ) internal returns (uint256 transferCount_) {
    require(
      transfers_.length == 1,
      "niftymoves: can only burn in a single transfer"
    );

    require(
      (transfers_[0].contractAddresses.length == transfers_[0].tokenIDs.length),
      "niftymoves: length mismatch, contracts and tokens lists"
    );

    for (
      uint256 collection = 0;
      collection < transfers_[0].contractAddresses.length;

    ) {
      uint256 item;

      // Collection is burnable. We burn by calling burn:
      for (item = 0; item < transfers_[0].tokenIDs[collection].length; ) {
        _efficient721Burn(
          sender_,
          transfers_[0].toAddress,
          transfers_[0].contractAddresses[collection],
          transfers_[0].tokenIDs[collection][item]
        );
        unchecked {
          item++;
        }
      }

      unchecked {
        transferCount_ += item;
        collection++;
      }
    }

    return (transferCount_);
  }

  /**
   *
   * @dev _performBurnsAsTrustedProvider: burn items on-chain.
   *
   * @param sender_: the calling address for this transaction
   * @param transfers_: the struct object containing the transfers
   * @param trustedProviderCollectionCount_: A count of collections in this
   * niftymove IF the UI has identified that one or more collections has
   * niftymoves as a trusted provider, and therefore qualifies for the bonus.
   *
   * @return transferCount_ : a count of the number of transfer transactions
   * @return bonuses_ : an array of bonus data structs
   *
   */
  function _performBurnsAsTrustedProvider(
    address sender_,
    Transfer[] calldata transfers_,
    uint256,
    uint256 trustedProviderCollectionCount_
  )
    internal
    returns (uint256 transferCount_, TrustedProviderBonuses[] memory bonuses_)
  {
    require(
      transfers_.length == 1,
      "niftymoves: can only burn in a single transfer"
    );

    require(
      (transfers_[0].contractAddresses.length == transfers_[0].tokenIDs.length),
      "niftymoves: length mismatch, contracts and tokens lists"
    );

    bonuses_ = new TrustedProviderBonuses[](trustedProviderCollectionCount_);
    uint256 bonusCount;

    for (
      uint256 collection = 0;
      collection < transfers_[0].contractAddresses.length;

    ) {
      uint256 item;

      // Collection is burnable. We burn by calling burn:
      for (item = 0; item < transfers_[0].tokenIDs[collection].length; ) {
        _efficient721Burn(
          sender_,
          transfers_[0].toAddress,
          transfers_[0].contractAddresses[collection],
          transfers_[0].tokenIDs[collection][item]
        );
        unchecked {
          item++;
        }
      }

      unchecked {
        // See if we have a collection wide discount through niftymoves
        // being included as a trusted service provider:
        if (
          trustedProviderCollectionCount_ != 0 &&
          _isTrustedProvider(transfers_[0].contractAddresses[collection])
        ) {
          // Collection has loaded niftymoves as a trusted provider. Record bonuses for distribution:
          bonuses_[bonusCount] = TrustedProviderBonuses(
            transfers_[0].contractAddresses[collection],
            item
          );
          bonusCount++;
        }
        transferCount_ += item;
        collection++;
      }
    }

    if (bonusCount != 0) {
      // Trim the list if is has more entries than we needed:
      if (trustedProviderCollectionCount_ > bonusCount) {
        assembly {
          let decrease := sub(trustedProviderCollectionCount_, bonusCount)
          mstore(bonuses_, sub(mload(bonuses_), decrease))
        }
      }
    }

    return (transferCount_, bonuses_);
  }

  /**
   *
   * @dev _efficient721Burn: burn items to the zero address
   *
   * @param from_: the calling address for this transaction
   * @param to_: the address to which items are being transferred
   * @param contract_: the contract for the items being transferred
   * @param tokenId_: the tokenId being transferred
   *
   */
  function _efficient721Burn(
    address from_,
    address to_,
    address contract_,
    uint256 tokenId_
  ) internal {
    // Check burning to address(0):
    require(to_ == address(0), "niftymoves: can only burn to zero address");

    // Check ownership:
    require(
      IERC721(contract_).ownerOf(tokenId_) == from_,
      "niftymoves: burn call from non owner"
    );

    // Perform burn:
    bool success;
    assembly {
      let burnData := add(0x20, mload(0x40))
      mstore(
        burnData,
        0x42966c6800000000000000000000000000000000000000000000000000000000
      )
      mstore(add(burnData, 0x04), tokenId_)
      success := call(gas(), contract_, 0, burnData, 0x24, 0, 0)
      // This has failed. Failures are not bubbled up the call stack (for example in the case of
      // the caller not being the owner of the token). We could pass back a custom error saying
      // the burn has failed as follows. We won't (see below), but code provided here in
      // comments for anyone wishing to see the approach.
      // 0x016f84a1 is the selector of {BurnFailed}.
      // if iszero(success) {
      //   mstore(
      //     0x00,
      //     0x016f84a100000000000000000000000000000000000000000000000000000000
      //   )
      //   // Store the tokenContract address at the beginning of the error data
      //   mstore(0x04, contract_)
      //   // Store the tokenId immediately after the tokenContract address
      //   mstore(0x24, tokenId_)
      //   revert(0x00, 0x44)
      // }
    }

    if (!success) {
      // Contract call to return reason up call stack. This will cost a bit more gas
      // than handling the error in assembly and returning an error (e.g. BurnFailed)
      // directly from this contract. But that would remove all detail from the returned error
      // message, making it far harder for the end user to understand the reason for the
      // failure. Note in all cases the app should apply pre-call validation to avoid such
      // errors costing *any* gas.
      ERC721Burnable(contract_).burn(tokenId_);
    }
  }

  /**
   *
   * @dev _processFees: process fees (if any)
   *
   * @param value_: the ETH sent with this call
   * @param transferCount_: the number of transfers made
   * @param discountDetails_: details of the discount being claimed
   * @param gasLimit_: The gas limit, if any, on referrer payments
   * @param proof_: proof for discount checks
   *
   */
  function _processFees(
    uint256 value_,
    uint256 transferCount_,
    DiscountParameters calldata discountDetails_,
    uint256 gasLimit_,
    bytes32[] calldata proof_
  ) internal returns (uint256 referrerPayment_) {
    // Calculate the base fee required:
    uint256 baseFee = transferFee * transferCount_;
    uint256 feeToPay;

    // See if we have a referral ID or a discount to apply based on holding.
    // In both cases the contractOrPayee will be non-zero:
    if (discountDetails_.contractOrPayee == address(0)) {
      // If we are here there is no discount to be applied.
      feeToPay = baseFee;
      referrerPayment_ = 0;
    } else {
      (feeToPay, referrerPayment_) = _processDiscountOrReferral(
        baseFee,
        discountDetails_,
        gasLimit_,
        proof_
      );
    }
    require(value_ == feeToPay, "niftymoves: incorrect payment");

    return (referrerPayment_);
  }

  /**
   *
   * @dev _processDiscountOrReferral: process details for either a referral or a discount
   *
   * @param baseFee_: the ETH required for this call before discounts
   * @param discountDetails_: details of the discount being claimed
   * @param gasLimit_: The gas limit, if any, on referrer payments
   * @param proof_: The merkle proof
   *
   * @return feePaid_ : the total fee to pay
   * @return referrerPayment_ : any referrer payment for the transaction
   *
   */
  function _processDiscountOrReferral(
    uint256 baseFee_,
    DiscountParameters calldata discountDetails_,
    uint256 gasLimit_,
    bytes32[] calldata proof_
  ) internal returns (uint256 feePaid_, uint256 referrerPayment_) {
    // Validate the provided details against the root:
    require(
      rootIsValid(proof_, discountDetails_),
      "niftymoves: invalid discount details for root"
    );

    // Check for a referral ID:
    if (discountDetails_.referralID != bytes12(0)) {
      // We have a referralID. Perform referral processing:
      (feePaid_, referrerPayment_) = _processReferral(
        baseFee_,
        discountDetails_,
        gasLimit_
      );
    } else {
      // If we reach here we must be processing a discount based on holding:
      (feePaid_) = _processDiscount(baseFee_, discountDetails_);
    }
  }

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
  ) public view returns (bool valid_) {
    bytes32 leaf = keccak256(
      abi.encodePacked(
        discountDetails_.contractOrPayee,
        discountDetails_.referralID,
        discountDetails_.tokenID1155,
        discountDetails_.minimumBalance,
        discountDetails_.discountBasisPoints,
        discountDetails_.referrerBasisPoints
      )
    );

    return (MerkleProof.verify(proof_, discountRoot, leaf));
  }

  /**
   *
   * @dev _processReferral: process fees associated with a referral
   *
   * @param baseFee_: the ETH required for this call before discounts
   * @param discountDetails_: details of the discount being claimed
   * @param gasLimit_: The gas limit, if any, on referrer payments
   *
   * @return feePaid_ : the total fee to pay
   * @return referrerPayment_ : any referrer payment for the transaction
   *
   */
  function _processReferral(
    uint256 baseFee_,
    DiscountParameters calldata discountDetails_,
    uint256 gasLimit_
  ) internal returns (uint256 feePaid_, uint256 referrerPayment_) {
    // Calculate the discount:
    (feePaid_) = _calculateDiscount(
      baseFee_,
      discountDetails_.discountBasisPoints
    );

    // Calculate the referral payment as a percentage of the discounted payment:
    referrerPayment_ = ((feePaid_ * discountDetails_.referrerBasisPoints) /
      DENOMINATOR_BASIS_POINTS);

    if (referrerPayment_ > 0) {
      // If gas limit is zero or greater than gas left, use the remaining gas.
      uint256 gas = (gasLimit_ == 0 || gasLimit_ > gasleft())
        ? gasleft()
        : gasLimit_;

      (bool success, ) = discountDetails_.contractOrPayee.call{
        value: referrerPayment_,
        gas: gas
      }("");
      // If the ETH transfer fails, wrap the ETH and try send it as WETH.
      if (!success) {
        wethContract.deposit{value: referrerPayment_}();
        IERC20(address(wethContract)).safeTransfer(
          discountDetails_.contractOrPayee,
          referrerPayment_
        );
      }
    }

    return (feePaid_, referrerPayment_);
  }

  /**
   *
   * @dev _processDiscount: process fees associated with a holding discount
   *
   * @param baseFee_: the ETH required for this call before discounts
   * @param discountDetails_: details of the discount being claimed
   *
   * @return feePaid_ : the total fee to pay
   *
   */
  function _processDiscount(
    uint256 baseFee_,
    DiscountParameters calldata discountDetails_
  ) internal view returns (uint256 feePaid_) {
    // Check they hold the required balance:
    require(
      _hasSufficientBalance(
        discountDetails_.contractOrPayee,
        discountDetails_.tokenID1155,
        discountDetails_.minimumBalance
      ),
      "niftymoves: insufficient holding for discount"
    );

    // Calculate the discount:
    feePaid_ = _calculateDiscount(
      baseFee_,
      discountDetails_.discountBasisPoints
    );

    return (feePaid_);
  }

  /**
   *
   * @dev _calculateDiscount: calculate the discount and therefore fee required
   *
   * @param baseFee_: the ETH required for this call before discounts
   * @param discountBasisPoints_: basis points of the discount
   *
   * @return feePaid_ : the total fee to pay
   *
   */
  function _calculateDiscount(
    uint256 baseFee_,
    uint256 discountBasisPoints_
  ) internal pure returns (uint256 feePaid_) {
    // Calculate the fee required given the discount:
    feePaid_ = (baseFee_ -
      ((baseFee_ * discountBasisPoints_) / DENOMINATOR_BASIS_POINTS));

    return (feePaid_);
  }

  /**
   *
   * @dev _hasSufficientBalance: check the caller holds a sufficient balance for the discount
   *
   * @param contractAddress_: the contract on which to check the holder's balance
   * @param tokenID1155_: this is populated if we need to check an 1155 balance
   * @param minimumBalance_: the minimum balance requirement for this discount
   *
   * @return hasBalance_ : if the holder has sufficient balance (or not)
   *
   */
  function _hasSufficientBalance(
    address contractAddress_,
    uint256 tokenID1155_,
    uint256 minimumBalance_
  ) internal view returns (bool hasBalance_) {
    if (tokenID1155_ != 0) {
      // Perform 1155 balance check
      return _balanceCheck1155(contractAddress_, tokenID1155_, minimumBalance_);
    } else {
      // Perform ERC721 / 20 / 777 check
      return (IERC721(contractAddress_).balanceOf(_msgSender()) >=
        minimumBalance_);
    }
  }

  /**
   *
   * @dev _balanceCheck1155: check the caller holds a sufficient balance for the discount
   *
   * @param contractAddress_: the contract on which to check the holder's balance
   * @param tokenID1155_: this is populated if we need to check an 1155 balance
   * @param minimumBalance_: the minimum balance requirement for this discount
   *
   * @return hasBalance_ : if the holder has sufficient balance (or not)
   *
   */
  function _balanceCheck1155(
    address contractAddress_,
    uint256 tokenID1155_,
    uint256 minimumBalance_
  ) internal view returns (bool hasBalance_) {
    // Perform 1155 check:
    uint256 tokenIDToCheck;
    if (tokenID1155_ == type(uint256).max) {
      tokenIDToCheck = 0;
    } else {
      tokenIDToCheck = tokenID1155_;
    }
    return (IERC1155(contractAddress_).balanceOf(
      _msgSender(),
      tokenIDToCheck
    ) >= minimumBalance_);
  }

  /**
   *
   * @dev onERC721Received: allow transfer from owner (for the ENS token).
   *
   * @param from_: used to check this is only from the contract owner
   *
   */
  function onERC721Received(
    address,
    address from_,
    uint256,
    bytes memory
  ) external view override returns (bytes4) {
    if (from_ == owner()) {
      return this.onERC721Received.selector;
    } else {
      return ("");
    }
  }

  /**
   *
   * @dev Revert unexpected ETH
   *
   */
  receive() external payable {
    require(
      _msgSender() == owner(),
      "niftymoves: only owner can fund contract"
    );
  }

  /**
   *
   * @dev Revert unexpected function calls
   *
   */
  fallback() external payable {
    revert();
  }
}
