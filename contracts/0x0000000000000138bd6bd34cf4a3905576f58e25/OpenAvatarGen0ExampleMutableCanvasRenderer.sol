// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {OpenAvatarGen0Renderer} from '../../OpenAvatarGen0Renderer.sol';

/**
 * @title OpenAvatarGen0ExampleMutableCanvasRenderer
 * @dev This contract renders a DNA as an image in a variety of formats,
 * and allows for mutating the canvas id by the contract owner.
 */
contract OpenAvatarGen0ExampleMutableCanvasRenderer is OpenAvatarGen0Renderer {
  error CanvasDoesNotExist(uint8 canvasId);

  // solhint-disable-next-line no-empty-blocks
  constructor(address ownerProxy) OpenAvatarGen0Renderer(ownerProxy) {}

  /**
   * @notice Set the canvas ID.
   * @param newCanvasId The new canvas ID.
   */
  function setCanvasId(uint8 newCanvasId) external onlyOwner {
    if (!openAvatarGen0AssetsRead.hasCanvas(newCanvasId)) revert CanvasDoesNotExist(newCanvasId);
    canvasId = newCanvasId;
  }
}
