// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {ERC721A, ERC721AQueryable, IERC721A} from 'erc721a/contracts/extensions/ERC721AQueryable.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

import {Base64} from '../../dependencies/Base64.sol';
import {ImageEncoder} from '../ImageEncoder.sol';

/**
 * @title TestSVGRenderer
 * @dev This contract is used for testing how websites render SVGs differently.
 *
 * Every token is rendered with a different "image" element where the SVG has
 * different formatting, attributes, workarounds, foreign objects, etc.
 *
 * This allows us to mint a bunch of tokens at once in the constructor and then
 * test how different websites render the SVGs on a testnet.
 */
contract TestSVGRenderer is ImageEncoder, ERC721AQueryable {
  using Strings for uint256;

  // SVG 1: Testing a simple SVG rendering with specific viewBox and fill color
  string private constant svg1 =
    '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">\n'
    '    <rect width="100" height="100" fill="#FF0000" />\n'
    '</svg>';

  // SVG 2: Similar to SVG 1, but with an overlapping green rectangle
  string private constant svg2 =
    '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">\n'
    '    <rect width="100" height="100" fill="#FF0000" />\n'
    '    <rect width="10" height="10" fill="#00FF00" />\n'
    '</svg>';

  // SVG 3: black border
  string private constant svg3 =
    '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">\n'
    '    <rect x="0" y="0" width="100" height="100" fill="none" stroke="#FF0000" />\n'
    '</svg>';

  // SVG 4: Testing overlapping circles with alpha transparency (Venn diagram) with border
  string private constant svg4 =
    '<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">\n'
    '    <rect x="0" y="0" width="120" height="120" fill="none" stroke="#FF0000" />\n'
    '    <circle cx="40" cy="60" r="30" fill="rgba(255, 0, 0, 0.5)" />\n'
    '    <circle cx="80" cy="60" r="30" fill="rgba(0, 255, 0, 0.5)" />\n'
    '    <circle cx="60" cy="40" r="30" fill="rgba(0, 0, 255, 0.5)" />\n'
    '</svg>';

  string private constant url =
    'https://raw.githubusercontent.com/stoooops/explore/master/image_rgba_32x32_cyan_checkerboard.png';

  /////////////////////////////////////////////////////////////////////////////
  // Constructor
  /////////////////////////////////////////////////////////////////////////////

  constructor() ERC721A('SVG Test', 'SVG') {
    // mint 100 tokens
    // _mintBatchTo(msg.sender, 100);
  }

  /////////////////////////////////////////////////////////////////////////////
  // ERC721Metadata
  /////////////////////////////////////////////////////////////////////////////

  function tokenURI(uint tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
    if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

    return
      string(
        abi.encodePacked(
          'data:application/json;base64,',
          Base64.encode(
            abi.encodePacked(
              '{"description":"TestSVGRenderer is a test contract for testing how base64-encoded SVGs are rendered on NFT marketplace websites.","image":"',
              getImageURI(tokenId),
              '","attributes":[{"trait_type":"Token ID","value":',
              tokenId.toString(),
              ',"display_type":"number"}]}'
            )
          )
        )
      );
  }

  /////////////////////////////////////////////////////////////////////////////
  // Art
  /////////////////////////////////////////////////////////////////////////////

  function packSVG(string memory svg) internal pure returns (bytes memory) {
    return abi.encodePacked('data:image/svg+xml;base64,', Base64.encode(abi.encodePacked(svg)));
  }

  function packPNG(bytes memory png) internal pure returns (bytes memory) {
    return abi.encodePacked('data:image/png;base64,', Base64.encode(png));
  }

  function getImageURI(uint tokenId) internal pure returns (bytes memory) {
    uint width = 32;
    uint height = 32;
    uint scaleWidth = 128;
    uint scaleHeight = 128;
    bytes memory checkerboard = fill(width, height, 0, 0, 255, 255);

    bytes memory imageUri;
    if (tokenId == 1) {
      imageUri = packSVG(svg1);
    } else if (tokenId == 2) {
      imageUri = packSVG(svg2);
    } else if (tokenId == 3) {
      imageUri = packSVG(svg3);
    } else if (tokenId == 4) {
      imageUri = packSVG(svg4);
    } else if (tokenId == 5) {
      imageUri = packPNG(encodePNG(checkerboard, width, height, true));
    } else if (tokenId == 6) {
      imageUri = packSVG(encodePNGBase64ImageSVG(checkerboard, width, height, true, scaleWidth, scaleHeight, false));
    } else if (tokenId == 7) {
      imageUri = packSVG(encodePNGBase64ImageSVG(checkerboard, width, height, true, scaleWidth, scaleHeight, true));
    } else if (tokenId == 8) {
      imageUri = packSVG(encodePNGBase64ForeignObjectSVG(checkerboard, width, height, true, scaleWidth, scaleHeight));
    } else if (tokenId == 9) {
      imageUri = packSVG(string(encodeSVG(checkerboard, width, height, true, scaleWidth, scaleHeight)));
    } else if (tokenId == 10) {
      imageUri = packSVG(encodeImageURLForeignObjectSVG(url, scaleWidth, scaleHeight));
    } else {
      // do nothing
    }

    return imageUri;
  }

  function fill(
    uint width,
    uint height,
    uint8 red,
    uint8 green,
    uint8 blue,
    uint8 alpha
  ) internal pure returns (bytes memory) {
    bytes memory result = new bytes(width * height * 4);
    for (uint i = 0; i < height; i++) {
      for (uint j = 0; j < width; j++) {
        uint offset = (i * width + j) * 4;
        // color the pixel if its row number and column number add up to an even number
        if ((i + j) % 2 == 0) {
          result[offset] = bytes1(red);
          result[offset + 1] = bytes1(green);
          result[offset + 2] = bytes1(blue);
          result[offset + 3] = bytes1(alpha);
        }
      }
    }
    return result;
  }

  // Helper function to create SVG start tag
  function startSVG(uint svgWidth, uint svgHeight, bool isForeignObject) internal pure returns (bytes memory) {
    string memory svgWidthStr = Strings.toString(svgWidth);
    string memory svgHeightStr = Strings.toString(svgHeight);

    if (isForeignObject) {
      return
        abi.encodePacked(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ',
          svgWidthStr,
          ' ',
          svgHeightStr,
          '">\n'
        );
    } else {
      return
        abi.encodePacked(
          '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ',
          svgWidthStr,
          ' ',
          svgHeightStr,
          '">\n'
        );
    }
  }

  // Helper function to close SVG
  function closeSVG() internal pure returns (bytes memory) {
    return '</svg>';
  }

  // Helper function to add a border to SVG
  function addBorder(uint svgWidth, uint svgHeight) internal pure returns (bytes memory) {
    string memory svgWidthStr = Strings.toString(svgWidth);
    string memory svgHeightStr = Strings.toString(svgHeight);

    return
      abi.encodePacked(
        '\t<rect x="0" y="0" width="',
        svgWidthStr,
        '" height="',
        svgHeightStr,
        '" fill="none" stroke="#FF0000" />\n'
      );
  }

  function encodePNGBase64ImageSVG(
    bytes memory data,
    uint width,
    uint height,
    bool alpha,
    uint svgWidth,
    uint svgHeight,
    bool usePixelatedRendering
  ) public pure returns (string memory) {
    bytes memory base64PNG = encodeBase64PNG(data, width, height, alpha);
    bytes memory result = startSVG(svgWidth, svgHeight, false);
    // result = abi.encodePacked(result, addBorder(svgWidth, svgHeight));

    string memory imageRendering = usePixelatedRendering ? ' style="image-rendering: pixelated;"' : '';

    result = abi.encodePacked(
      result,
      '\t<image x="0" y="0" width="',
      Strings.toString(svgWidth),
      '" height="',
      Strings.toString(svgHeight),
      '" preserveAspectRatio="none" xlink:href="data:image/png;base64,',
      base64PNG,
      '"',
      imageRendering,
      '/>\n',
      closeSVG()
    );

    return string(result);
  }

  function encodePNGBase64ForeignObjectSVG(
    bytes memory data,
    uint width,
    uint height,
    bool alpha,
    uint svgWidth,
    uint svgHeight
  ) public pure returns (string memory) {
    bytes memory base64PNG = encodeBase64PNG(data, width, height, alpha);
    bytes memory result = startSVG(svgWidth, svgHeight, true);
    // result = abi.encodePacked(result, addBorder(svgWidth, svgHeight));
    result = abi.encodePacked(
      result,
      '\t<foreignObject width="',
      Strings.toString(svgWidth),
      '" height="',
      Strings.toString(svgHeight),
      '">\n'
    );
    result = abi.encodePacked(
      result,
      '\t\t<img xmlns="http://www.w3.org/1999/xhtml" width="',
      Strings.toString(svgWidth),
      '" height="',
      Strings.toString(svgHeight),
      '" style="image-rendering: pixelated;" src="data:image/png;base64,',
      base64PNG,
      '"/>\n'
    );
    result = abi.encodePacked(result, '\t</foreignObject>\n', closeSVG());

    return string(result);
  }

  function encodeImageURLForeignObjectSVG(
    string memory imageURL,
    uint svgWidth,
    uint svgHeight
  ) public pure returns (string memory) {
    bytes memory result = startSVG(svgWidth, svgHeight, true);
    // result = abi.encodePacked(result, addBorder(svgWidth, svgHeight));

    result = abi.encodePacked(
      result,
      '\t<foreignObject width="',
      Strings.toString(svgWidth),
      '" height="',
      Strings.toString(svgHeight),
      '">\n\t\t<img xmlns="http://www.w3.org/1999/xhtml" width="',
      Strings.toString(svgWidth),
      '" height="',
      Strings.toString(svgHeight),
      '" style="image-rendering: pixelated;" src="',
      bytes(imageURL),
      '"/>\n\t</foreignObject>\n',
      closeSVG()
    );

    return string(result);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Mint
  /////////////////////////////////////////////////////////////////////////////

  function _mintTo(address to) internal {
    _safeMint(to, 1);
  }

  function mint() external payable {
    _mintTo(msg.sender);
  }

  function mintTo(address to) external payable {
    _mintTo(to);
  }

  function _mintBatchTo(address to, uint n) internal {
    _safeMint(to, n);
  }

  function mintBatch(uint n) external payable {
    _mintBatchTo(msg.sender, n);
  }

  function mintBatchTo(address to, uint n) external payable {
    _mintBatchTo(to, n);
  }
}
