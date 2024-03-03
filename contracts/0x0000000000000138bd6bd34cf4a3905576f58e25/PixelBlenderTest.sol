// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PixelBlender} from '../PixelBlender.sol';

contract PixelBlenderTest is PixelBlender {
  function testBlendPixel(uint8 foreground, uint8 background, uint8 foregroundAlpha) public pure returns (uint8) {
    return blendPixel(foreground, background, foregroundAlpha);
  }

  function testBlendAlpha(uint8 foregroundAlpha, uint8 backgroundAlpha) public pure returns (uint8) {
    return blendAlpha(foregroundAlpha, backgroundAlpha);
  }
}
