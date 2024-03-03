// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {FuseGuard} from '../lib/FuseGuard.sol';

/**
 * @title AOpenAvatarMintStateMachine
 * @notice A contract that manages the mint state machine.
 */
abstract contract AOpenAvatarMintStateMachine is FuseGuard, Ownable {
  /// @dev The mint states.
  enum MintState {
    PermanentlyDisabled,
    Disabled,
    OnlyOwner,
    PublicPendingBlockTimestamp,
    Public
  }

  /// @dev Event emitted when the fuse is burned to disable changing the mint state.
  event FuseBurnedCanChangeMintState();
  /// @dev Event emitted when the fuse is burned to disable changing the public mint time.
  event FuseBurnedCanChangePublicMintTime();
  /// @dev Event emitted when the mint state changes.
  event MintStateChange(MintState state);
  /// @dev Event emitted when the public mint time changes.
  event PublicMintTimeChange(uint time);

  /// @dev Revert error when mint is permanently disabled.
  error MintPermanentlyDisabled();
  /// @dev Revert error when public mint is not yet started.
  error PublicMintNotStarted();
  /// @dev Revert error when public mint is disabled.
  error MintDisabled();
  /// @dev Revert error when public mint is not authorized.
  error MintNotAuthorized();

  /////////////////////////////////////////////////////////////////////////////
  // Internal Data Structures
  /////////////////////////////////////////////////////////////////////////////

  /// @dev The current mint state.
  MintState public mintStatus = MintState.Disabled;

  /// @dev The time when public minting will be enabled, if pending public mint time.
  uint256 public publicMintTime;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for changing the mint state.
  bool public fuseBurnedCanChangeMintState = false;
  /// @dev Flag to indicate if the fuse has been burned for changing the public mint time.
  bool public fuseBurnedCanChangePublicMintTime = false;

  /**
   * @notice Sets whether mint is active.
   * @param val True to enable mint, false to disable.
   * @dev Only callable by owner.
   * @dev reverts if mint is fuse is burned
   * @dev no-op if mint is already set to the desired value
   * @dev reverts if mint is permanently disabled
   */
  function setMintState(MintState val) external onlyOwner {
    if (fuseBurnedCanChangeMintState) revert OperationBlockedByBurnedFuse();
    if (val == mintStatus) return;
    if (mintStatus == MintState.PermanentlyDisabled) revert MintPermanentlyDisabled();
    mintStatus = val;
    emit MintStateChange(val);
  }

  /**
   * @notice Burn the fuse to permanently disable changing the mint state.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanChangeMintState() external onlyOwner {
    if (fuseBurnedCanChangeMintState) return;
    fuseBurnedCanChangeMintState = true;
    emit FuseBurnedCanChangeMintState();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable changing the mint state.
   * @return Whether the fuse is burned to permanently disable changing the mint state.
   */
  function isFuseBurnedCanChangeMintState() external view returns (bool) {
    return fuseBurnedCanChangeMintState;
  }

  /**
   * @notice Get the public mint time.
   * @return The public mint time.
   */
  function getPublicMintTime() external view returns (uint256) {
    return publicMintTime;
  }

  /**
   * @notice Set the public mint time.
   * @param _publicMintTime The public mint time.
   * @dev reverts if fuse is burned
   */
  function setPublicMintTime(uint256 _publicMintTime) external onlyOwner {
    if (fuseBurnedCanChangePublicMintTime) revert OperationBlockedByBurnedFuse();
    if (publicMintTime == _publicMintTime) return;
    publicMintTime = _publicMintTime;
    emit PublicMintTimeChange(_publicMintTime);
  }

  /**
   * @notice Burn the fuse to permanently disable changing the public mint time.
   * @dev Only callable by owner.
   * @dev no-op if fuse is already burned
   */
  function burnFuseCanChangePublicMintTime() external onlyOwner {
    if (fuseBurnedCanChangePublicMintTime) return;
    fuseBurnedCanChangePublicMintTime = true;
    emit FuseBurnedCanChangePublicMintTime();
  }

  /**
   * @notice Returns whether the fuse is burned to permanently disable changing the public mint time.
   * @return Whether the fuse is burned to permanently disable changing the public mint time.
   */
  function isFuseBurnedCanChangePublicMintTime() external view returns (bool) {
    return fuseBurnedCanChangePublicMintTime;
  }

  /**
   * @notice Returns the current mint state.
   * @return The current mint state.
   */
  function getMintState() external view returns (MintState) {
    return mintStatus;
  }

  /**
   * @notice Returns whether mint state is public.
   * @return True if mint state is public, false otherwise.
   */
  function isMintPublic() external view returns (bool) {
    return mintStatus == MintState.Public;
  }

  /**
   * @notice Returns whether mint state is public pending block timestamp.
   * @return True if mint state is public pending block timestamp, false otherwise.
   */
  function isMintPublicPendingBlockTimestamp() external view returns (bool) {
    return mintStatus == MintState.PublicPendingBlockTimestamp;
  }

  /**
   * @notice Returns whether mint state is only owner can mint.
   * @return True if mint state is only owner can mint, false otherwise.
   */
  function isMintOnlyOwner() external view returns (bool) {
    return mintStatus == MintState.OnlyOwner;
  }

  /**
   * @notice Returns whether mint state is paused or permanently disabled.
   * @return True if mint state is paused or permanently disabled, false otherwise.
   */
  function isMintDisabled() external view returns (bool) {
    return mintStatus == MintState.Disabled || mintStatus == MintState.PermanentlyDisabled;
  }

  /**
   * @notice Returns whether mint state is permanently disabled.
   * @return True if mint state is permanently disabled, false otherwise.
   */
  function isMintPermanentlyDisabled() external view returns (bool) {
    return mintStatus == MintState.PermanentlyDisabled;
  }

  ////////////////////////// modifiers //////////////////////////

  /**
   * @notice Modifier to check if mint is public.
   * ----------------------------------------------------------------------
   * |  MintState                     |  Owner  |  Non-owner  |  Result  |
   * ----------------------------------------------------------------------
   * |  PermanentlyDisabled           |   No    |     No      |  Revert  |
   * ----------------------------------------------------------------------
   * |  Disabled                      |   No    |     No      |  Revert  |
   * ----------------------------------------------------------------------
   * |  OnlyOwner                     |   Yes   |     No      |  Proceed |
   * ----------------------------------------------------------------------
   * |  PublicPendingBlockTimestamp   |   No    |     No      |  Revert  |
   * |  (Before Time)                 |         |             |          |
   * ----------------------------------------------------------------------
   * |  PublicPendingBlockTimestamp   |   Yes   |     Yes     |  Proceed |
   * |  (At/After Time)               |         |             |          |
   * ----------------------------------------------------------------------
   * |  Public                        |   Yes   |     Yes     |  Proceed |
   * ----------------------------------------------------------------------
   * @dev Reverts if mint is not authorized.
   */
  modifier onlyAuthorizedMint() {
    if (mintStatus == MintState.Public) {
      // CASE 1: mint is public
      _;
    } else if (mintStatus == MintState.PublicPendingBlockTimestamp) {
      // CASE 2: mint is public pending block timestamp
      //
      // in our normal scenario, this will only happen once, unless contract owner puts it back to public
      // pending block timestamp
      //
      // we are going to check the block timestamp to see if it is greater than or equal to the public mint time
      // if it is, we will update the mint state to public
      // otherwise, we will revert with an error
      //
      // solhint-disable-next-line not-rely-on-time
      if (block.timestamp < publicMintTime) {
        // CASE 2.1: && block timestamp is NOT greater than public mint time
        // => mint is not yet public so revert
        //
        // this happens if callers try to mint before the public mint time
        //
        revert PublicMintNotStarted();
      } else {
        // CASE 2.2: && block timestamp IS greater than or equal public mint time
        // => update the mint state to public
        // => mint is now public so continue
        //
        // this will only happen once, unless contract owner puts it back to public
        // pending block timestamp
        //
        mintStatus = MintState.Public;
        emit MintStateChange(MintState.Public);
      }
    } else if (mintStatus == MintState.OnlyOwner) {
      // CASE 3: mint is only owner
      //
      // this should be the normal scenario with a single boolean check
      if (owner() == _msgSender()) {
        // CASE 3.1: && caller is owner
        // => mint is only owner && caller is owner so continue
        _;
      } else {
        // CASE 3.2: && caller is NOT owner
        // => mint is only owner && caller is NOT owner so revert
        revert MintNotAuthorized();
      }
    } else if (mintStatus == MintState.Disabled) {
      revert MintDisabled();
    } else {
      revert MintPermanentlyDisabled();
    }
  }
}
