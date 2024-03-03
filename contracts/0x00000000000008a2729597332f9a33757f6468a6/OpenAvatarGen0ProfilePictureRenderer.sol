// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {OpenAvatarGen0AssetsCanvasIdStore} from '../core/assets/OpenAvatarGen0AssetsCanvasIdStore.sol';
import {IOpenAvatarGen0CanvasRenderer} from '../core/interfaces/render/IOpenAvatarGen0CanvasRenderer.sol';
import {ENSReverseClaimer} from '../core/lib/ENSReverseClaimer.sol';
import {ImageEncoder} from '../core/lib/ImageEncoder.sol';
import {KeepAlive} from '../core/lib/KeepAlive.sol';
import {IOpenAvatarGen0AssetsRead} from '../IOpenAvatarGen0Assets.sol';
import {IOpenAvatarGen0Renderer} from '../IOpenAvatarGen0Renderer.sol';
import {IOpenAvatarGen0TextRecords} from '../IOpenAvatarGen0TextRecords.sol';
import {IOpenAvatarGen0TokenDNA} from '../IOpenAvatarGen0Token.sol';
import {OpenAvatarGenerationZero} from '../OpenAvatarGenerationZero.sol';
import {DNA} from '../core/lib/DNA.sol';
import {IOpenAvatarGen0AssetsCanvasLayerCompositor, LayerPatternPalette} from '../core/interfaces/render/IOpenAvatarGen0AssetsCanvasLayerCompositor.sol';

struct OpenAvatarProfilePictureSettings {
  /// @dev Whether or not to use a solid background color.
  bool overrideBackground;
  /// @dev The background color.
  bytes3 backgroundColor;
  /// @dev Whether or not to mask below the neck for a "floating head" effect.
  bool maskBelowTheNeck;
}

/**
 * @title OpenAvatarGen0ProfilePictureRenderer
 * @author Cory Gabrielsen (cory.eth)
 *
 * @notice A contract for rendering OpenAvatar Gen0 profile pictures.
 * @dev This contract renders an Avatar against a background image.
 *
 * ----------------------------------------------------------------------------
 * 'pfp' Renderer
 * ----------------------------------------------------------------------------
 * A Profile Picture Renderer is provided with the key "pfp".
 *
 * The 'pfp' Renderer renders the Avatar with a configurable background color
 * determined by the 'gen0.renderer.pfp.background-color' text record, which
 * should be a valid RGB hex color code (e.g. "#ff0000" for red).
 *
 * Further, the 'pfp' Renderer provides the option of masking the Avatar
 * below the neck to create a "floating head" effect. This can be configured
 * by setting the `gen0.renderer.pfp.mask` text record to "below-the-neck".
 *
 * The Profile Picture Renderer is a demonstration of combining the OpenAvatar
 * building blocks together to create dynamic, owner-customizable behavior. It
 * utilizes onchain assets, onchain rendering, and onchain text records to
 * render a customizable Avatar pfp.
 *
 * This pattern is permissionless.
 *
 *
 * ----------------------------------------------------------------------------
 * Background Image
 * ----------------------------------------------------------------------------
 * The background image is by default a white/light gray checkerboard of 8x8
 * squares arranged in a 4x4 grid.
 *
 * The background image can be changed by the token owner by setting the
 * 'gen0.renderer.pfp.background-image' text record to a valid RGB hex color
 * code (e.g. "#ff0000" for red).
 */
contract OpenAvatarGen0ProfilePictureRenderer is
  IOpenAvatarGen0Renderer,
  OpenAvatarGenerationZero,
  OpenAvatarGen0AssetsCanvasIdStore,
  ImageEncoder,
  ENSReverseClaimer,
  KeepAlive
{
  using DNA for bytes32;

  /// @dev Emitted when the fuse is burned to make the background image immutable.
  event FuseBurnedChangeBackgroundImage();

  /// @dev Error when a component is already initialized.
  error AlreadyInitialized();
  /// @dev Error when the fuse is already burned.
  error FuseBurned();
  /// @dev Error when the required ERC-165 interfaces are not supported.
  error InterfaceUnsupported(address contractAddress, bytes4 interfaceId);
  /// @dev Error when the provided canvas has an invalid number of bytes per pixel.
  error InvalidCanvasBytesPerPixel();
  /// @dev Error when calling write-protection function on a non-owned DNA.
  error NotOwner(bytes32 dna);

  /// @dev The ERC-165 interface id for the OpenAvatarGen0Renderer (for clients).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_RENDERER = 0xb93e4881;
  /// @dev The ERC-165 interface id for the OpenAvatarGen0AssetsRead (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_READ = 0x67bf31d1;
  /// @dev The ERC-165 interface id for the OpenAvatarGen0AssetsCanvasLayerCompositor (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_CANVAS_LAYER_COMPOSITOR = 0x2638c94b;
  /// @dev The ERC-165 interface id for the OpenAvatarGen0TokenDNA (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA = 0x2717336f;
  /// @dev The ERC-165 interface id for the OpenAvatarGen0TextRecords ERC-634 text() (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_TEXT = 0x59d1d43c;

  /// @dev The canvas id.
  uint8 public constant CANVAS_ID = 0;
  /// @dev The pixel width of the canvas.
  uint8 public constant CANVAS_WIDTH = 32;
  /// @dev The pixel height of the canvas.
  uint8 public constant CANVAS_HEIGHT = 32;
  /// @dev The number of bytes in the canvas - 32 * 32 * 4.
  uint16 public constant CANVAS_NUM_BYTES = 4096;

  /// @dev The layer index for the body layer.
  uint8 public constant LAYER_INDEX_BODY = 10;
  /// @dev The layer index for the tattoos layer.
  uint8 public constant LAYER_INDEX_TATTOOS = 20;
  /// @dev The layer index for the makeup layer.
  uint8 public constant LAYER_INDEX_MAKEUP = 30;
  /// @dev The layer index for the left eye layer.
  uint8 public constant LAYER_INDEX_LEFT_EYE = 40;
  /// @dev The layer index for the right eye layer.
  uint8 public constant LAYER_INDEX_RIGHT_EYE = 50;
  /// @dev The layer index for the bottomwear layer.
  uint8 public constant LAYER_INDEX_BOTTOMWEAR = 60;
  /// @dev The layer index for the footwear layer.
  uint8 public constant LAYER_INDEX_FOOTWEAR = 70;
  /// @dev The layer index for the topwear layer.
  uint8 public constant LAYER_INDEX_TOPWEAR = 80;
  /// @dev The layer index for the handwear layer.
  uint8 public constant LAYER_INDEX_HANDWEAR = 90;
  /// @dev The layer index for the outerwear layer.
  uint8 public constant LAYER_INDEX_OUTERWEAR = 100;
  /// @dev The layer index for the jewelry layer.
  uint8 public constant LAYER_INDEX_JEWELRY = 110;
  /// @dev The layer index for the facial hair layer.
  uint8 public constant LAYER_INDEX_FACIAL_HAIR = 120;
  /// @dev The layer index for the facewear layer.
  uint8 public constant LAYER_INDEX_FACEWEAR = 130;
  /// @dev The layer index for the eyewear layer.
  uint8 public constant LAYER_INDEX_EYEWEAR = 140;
  /// @dev The layer index for the hair layer.
  uint8 public constant LAYER_INDEX_HAIR = 150;

  /// @dev Scale the SVG by this amount.
  uint public constant SVG_SCALE = 10;

  /// @dev The "only head" mask which masks below the neck.
  bytes public constant BELOW_THE_NECK_MASK =
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0000000000000000000000000000000000000000000000000000000000000000'
    hex'0101010101010101010101010000000000000000010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101'
    hex'0101010101010101010101010101010101010101010101010101010101010101';

  /// @dev The background image, an 4x4 grid of 8x8 checkerboard squares.
  ///      Every four lines is one row of the image.
  ///      The pattern switches every 8 rows, or 32 lines
  ///
  ///      This value is constant even though it isn't declared constant,
  ///      because declaring it as a constant makes renderURI fail
  ///      with out-of-gas?
  bytes public backgroundImage =
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff'
    hex'EEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEffEEEEEEff'
    hex'DDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDffDDDDDDff';

  /// @dev The text key for the background color of the avatar pfp.
  string public constant TEXT_KEY_PFP_BACKGROUND_COLOR = 'gen0.renderer.pfp.background-color';
  /// @dev The text key for the mask of the avatar pfp.
  string public constant TEXT_KEY_PFP_MASK = 'gen0.renderer.pfp.mask';
  /// @dev The text value for a pfp rendering that only displays the head.
  string public constant TEXT_KEY_PFP_MASK_VALUE_BELOW_THE_NECK = 'below-the-neck';
  /// @dev The keccak26 hash 'below-the-neck', for use in the contract.
  bytes32 private constant TEXT_KEY_PFP_MASK_VALUE_BELOW_THE_NECK_HASH =
    keccak256(abi.encodePacked(TEXT_KEY_PFP_MASK_VALUE_BELOW_THE_NECK));

  /////////////////////////////////////////////////////////////////////////////
  // State variables
  /////////////////////////////////////////////////////////////////////////////

  /// @dev fuse can be burned to make the background image immutable
  bool public fuseBurnedChangeBackgroundImage = false;

  /// @dev The OpenAvatarGen0AssetsRead dependency.
  IOpenAvatarGen0AssetsRead public openAvatarGen0AssetsRead;
  /// @dev The OpenAvatarGen0AssetsCanvasLayerCompositor dependency.
  IOpenAvatarGen0AssetsCanvasLayerCompositor public openAvatarGen0AssetsCanvasLayerCompositor;
  /// @dev The OpenAvatarDNA dependency.
  IOpenAvatarGen0TokenDNA public openAvatarGen0Token;
  /// @dev The OpenAvatarGen0TextRecords dependency.
  IOpenAvatarGen0TextRecords public openAvatarGen0TextRecords;

  // solhint-disable-next-line no-empty-blocks
  constructor(address ownerProxy) OpenAvatarGen0AssetsCanvasIdStore(CANVAS_ID) {
    // will be deployed by ImmutableCreate2Factory and then transferred to the configured owner
    // using a proxy allows for using same bytecode in test and prod

    address wantOwner = Ownable(ownerProxy).owner();
    if (owner() != wantOwner) {
      transferOwnership(wantOwner);
    }
  }

  /////////////////////////////////////////////////////////////////////////////
  // ERC-165: Standard Interface Detection
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Checks if the contract supports an interface.
   * @param interfaceId The interface identifier, as specified in ERC-165.
   * @return True if the contract supports interfaceID, false otherwise.
   */
  function supportsInterface(bytes4 interfaceId) public pure override(OpenAvatarGenerationZero) returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // IOpenAvatar
      interfaceId == 0xfdf02ac8 || // ERC165 interface ID for IOpenAvatarGeneration.
      interfaceId == 0x7b65147c || // ERC165 interface ID for IOpenAvatarSentinel.
      interfaceId == 0x86953eb4 || // ERC165 interface ID for IOpenAvatar.
      // renderer
      interfaceId == INTERFACE_ID_OPENAVATAR_GEN0_RENDERER;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Initialize Dependencies
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Initialize the contract.
   * @param openAvatarGen0Assets_ The address of the asset store read interface contract.
   * @param openAvatarAssesCanvasLayerCompositor_ The address of the canvas layer compositor contract.
   * @param openAvatarGen0Token_ The address of the OpenAvatar token contract.
   * @param openAvatarGen0TextRecords_ The address of the text records contract.
   */
  function initialize(
    address openAvatarGen0Assets_,
    address openAvatarAssesCanvasLayerCompositor_,
    address openAvatarGen0Token_,
    address openAvatarGen0TextRecords_
  ) external onlyOwner {
    // helpers enforce only-once invariant and check ERC-165 supportsInterface()
    setOpenAvatarGen0Assets(openAvatarGen0Assets_);
    setOpenAvatarGen0AssetsCanvasLayerCompositor(openAvatarAssesCanvasLayerCompositor_);
    setOpenAvatarGen0Token(openAvatarGen0Token_);
    setOpenAvatarGen0TextRecords(openAvatarGen0TextRecords_);
  }

  /**
   * @notice Check if the contract has been initialized.
   * @return True if the contract has been initialized, false otherwise.
   */
  function isInitialized() external view returns (bool) {
    return address(openAvatarGen0AssetsRead) != address(0);
  }

  /**
   * @notice Get the asset store.
   * @return The address of the asset store read interface contract.
   */
  function getOpenAvatarGen0Assets() external view returns (address) {
    return address(openAvatarGen0AssetsRead);
  }

  /**
   * @notice Set the asset store.
   * @param openAvatarGen0Assets_ The address of the asset store read interface contract.
   */
  function setOpenAvatarGen0Assets(address openAvatarGen0Assets_) internal {
    // only set once
    if (address(openAvatarGen0AssetsRead) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only read interface is required
    if (!IERC165(openAvatarGen0Assets_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_READ)) {
      revert InterfaceUnsupported(openAvatarGen0Assets_, INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_READ);
    }

    // set
    openAvatarGen0AssetsRead = IOpenAvatarGen0AssetsRead(openAvatarGen0Assets_);

    // sanity check
    if (openAvatarGen0AssetsRead.getBytesPerPixel() != 4) revert InvalidCanvasBytesPerPixel();
  }

  /**
   * @notice Get the IOpenAvatarGen0AssetsCanvasLayerCompositor.
   * @return The address of the IOpenAvatarGen0AssetsCanvasLayerCompositor interface contract.
   */
  function getOpenAvatarGen0AssetsCanvasLayerCompositor() external view returns (address) {
    return address(openAvatarGen0AssetsCanvasLayerCompositor);
  }

  /**
   * @notice Set the IOpenAvatarGen0AssetsCanvasLayerCompositor.
   * @param openAvatarAssesCanvasLayerCompositor_ The address of the
   * IOpenAvatarGen0AssetsCanvasLayerCompositor interface contract.
   */
  function setOpenAvatarGen0AssetsCanvasLayerCompositor(address openAvatarAssesCanvasLayerCompositor_) internal {
    // only set once
    if (address(openAvatarGen0AssetsCanvasLayerCompositor) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    //
    // we don't need use renderURI from OpenAvatarGen0Renderer, which is too high level here
    //
    // instead we use the compositor interface to manually layer assets on top of each other
    // allowing us to modify the image layers before encoding as a PNG/SVG
    if (
      !IERC165(openAvatarAssesCanvasLayerCompositor_).supportsInterface(
        INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_CANVAS_LAYER_COMPOSITOR
      )
    ) {
      revert InterfaceUnsupported(
        openAvatarAssesCanvasLayerCompositor_,
        INTERFACE_ID_OPENAVATAR_GEN0_ASSETS_CANVAS_LAYER_COMPOSITOR
      );
    }

    // set
    openAvatarGen0AssetsCanvasLayerCompositor = IOpenAvatarGen0AssetsCanvasLayerCompositor(
      openAvatarAssesCanvasLayerCompositor_
    );
  }

  /**
   * @notice Get the OpenAvatar token.
   * @return The address of the OpenAvatar token read interface contract.
   */
  function getOpenAvatarGen0Token() external view returns (address) {
    return address(openAvatarGen0Token);
  }

  /**
   * @notice Set the OpenAvatar token address.
   * @param openAvatarGen0Token_ The address of the OpenAvatar token contract.
   */
  function setOpenAvatarGen0Token(address openAvatarGen0Token_) internal {
    // only set once
    if (address(openAvatarGen0Token) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only DNA interface is required
    if (!IERC165(openAvatarGen0Token_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA)) {
      revert InterfaceUnsupported(openAvatarGen0Token_, INTERFACE_ID_OPENAVATAR_GEN0_TOKEN_DNA);
    }

    // set
    openAvatarGen0Token = IOpenAvatarGen0TokenDNA(openAvatarGen0Token_);
  }

  /**
   * @notice Get the OpenAvatarGen0TextRecords.
   * @return The address of the OpenAvatarGen0TextRecords.
   */
  function getOpenAvatarGen0TextRecords() external view returns (address) {
    return address(openAvatarGen0TextRecords);
  }

  /**
   * @notice Set the OpenAvatarGen0TextRecords address.
   * @param openAvatarGen0TextRecords_ The address of the OpenAvatarGen0TextRecords contract.
   */
  function setOpenAvatarGen0TextRecords(address openAvatarGen0TextRecords_) internal {
    // only set once
    if (address(openAvatarGen0TextRecords) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only text() interface is required
    if (!IERC165(openAvatarGen0TextRecords_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_TEXT)) {
      revert InterfaceUnsupported(openAvatarGen0TextRecords_, INTERFACE_ID_OPENAVATAR_GEN0_TEXT);
    }

    // set
    openAvatarGen0TextRecords = IOpenAvatarGen0TextRecords(openAvatarGen0TextRecords_);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Modifiers
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Modifier to check that the caller is the owner of the token.
   */
  modifier onlyTokenOwner(bytes32 dna) {
    if (msg.sender != openAvatarGen0Token.ownerOfDNA(dna)) {
      revert NotOwner(dna);
    }
    _;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Get the fuse burned status for changing the background image.
   */
  function getFuseBurnedChangeBackgroundImage() external view returns (bool) {
    return fuseBurnedChangeBackgroundImage;
  }

  /**
   * @dev Burn the fuse to prevent changing the background image.
   */
  function burnFuseChangeBackgroundImage() external onlyOwner {
    if (!fuseBurnedChangeBackgroundImage) {
      fuseBurnedChangeBackgroundImage = true;
      emit FuseBurnedChangeBackgroundImage();
    }
  }

  /////////////////////////////////////////////////////////////////////////////
  // Background Image
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Get the default background image.
   */
  function getBackgroundImage() external view returns (bytes memory) {
    return backgroundImage;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Profile Picture Settings
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Return the background settings for the given DNA.
   * @param dna The DNA to set the background color for.
   * @return The background settings.
   */
  function getProfilePictureSettings(bytes32 dna) external view returns (OpenAvatarProfilePictureSettings memory) {
    string memory pfpBackground = openAvatarGen0TextRecords.text(dna, TEXT_KEY_PFP_BACKGROUND_COLOR);

    // pfpBackground is a RGB hexstring like #AABBCC
    // we need to decompose into a bytes3 0xAABBCC
    bool overrideBackground = bytes(pfpBackground).length == 7;
    bytes3 backgroundColor = _hexStrToBytes3(pfpBackground);

    // pfpMask is a string like 'below-the-neck' or ''
    string memory pfpMask = openAvatarGen0TextRecords.text(dna, TEXT_KEY_PFP_MASK);
    // security (gas) - don't compute hash if incorrect length
    bool validLength = bytes(pfpMask).length == 14; // 'below-the-neck' is 14 bytes
    bool maskBelowTheNeck = false;
    if (validLength) {
      maskBelowTheNeck = keccak256(abi.encodePacked(pfpMask)) == TEXT_KEY_PFP_MASK_VALUE_BELOW_THE_NECK_HASH;
    }

    return OpenAvatarProfilePictureSettings(overrideBackground, backgroundColor, maskBelowTheNeck);
  }

  /**
   * @notice Convert an RGB hextring #AABBCC to a bytes3 0xAABBCC.
   * @param _str The string to convert.
   * @return The bytes3 value
   * @dev if the string is not length-7 or leading # is missing, return 0x000000
   * @dev if a pair of characters is not a valid hex string, return 0x00 for that byte
   */
  function _hexStrToBytes3(string memory _str) internal pure returns (bytes3) {
    bytes memory b = bytes(_str);
    if (b.length != 7) return 0x000000;

    // the first character should be '#'
    if (b[0] != 0x23) return 0x000000;

    bytes3 rgb;
    for (uint i = 0; i < 3; i++) {
      rgb |= bytes3(_safeParseByte(_str, 2 * i + 1)) >> (8 * i);
    }
    return rgb;
  }

  /**
   * @notice Safely parse a byte.
   * @param _str The string to parse.
   * @param _start The start index.
   * @return The parsed byte, or 0x00 if the byte is invalid.
   */
  function _safeParseByte(string memory _str, uint _start) private pure returns (bytes1) {
    bytes1 b1 = _safeParseHexDigit(bytes(_str)[_start]);
    bytes1 b2 = _safeParseHexDigit(bytes(_str)[_start + 1]);
    return (b1 << 4) | b2;
  }

  /**
   * @dev Safely parse a hex digit.
   * @param _hex The hex digit to parse.
   * @return The parsed digit, or 0x00 if the digit is invalid.
   */
  function _safeParseHexDigit(bytes1 _hex) private pure returns (bytes1) {
    if (_hex >= '0' && _hex <= '9') {
      return bytes1(uint8(_hex) - 48);
    }
    if (_hex >= 'a' && _hex <= 'f') {
      return bytes1(uint8(_hex) - 97 + 10);
    }
    if (_hex >= 'A' && _hex <= 'F') {
      return bytes1(uint8(_hex) - 65 + 10);
    }
    return 0;
  }

  /////////////////////////////////////////////////////////////////////////////
  // Rendering - external
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Render the given DNA as a base64-encoded SVG URI.
   * @param dna The DNA to render.
   * @return The SVG URI.
   */
  function renderURI(bytes32 dna) external view override returns (string memory) {
    return string(abi.encodePacked('data:image/svg+xml;base64,', renderBase64SVG(dna)));
  }

  /**
   * @notice Render the given DNA as a base64-encoded SVG URI with the provided settings.
   * @param dna The DNA to render.
   * @param pfpSettings The background settings to use.
   * @return The SVG URI.
   */
  function renderURIWithSettings(
    bytes32 dna,
    OpenAvatarProfilePictureSettings memory pfpSettings
  ) external view returns (string memory) {
    return string(abi.encodePacked('data:image/svg+xml;base64,', renderBase64SVGWithSettings(dna, pfpSettings)));
  }

  /////////////////////////////////////////////////////////////////////////////
  // Rendering - helpers
  /////////////////////////////////////////////////////////////////////////////

  function createBackgroundImage(
    OpenAvatarProfilePictureSettings memory pfpSettings
  ) internal view returns (bytes memory, uint8, uint8) {
    bytes memory image = new bytes(openAvatarGen0AssetsRead.getCanvasNumBytes(canvasId));

    uint8 width = openAvatarGen0AssetsRead.getCanvasWidth(canvasId);
    uint8 height = openAvatarGen0AssetsRead.getCanvasHeight(canvasId);

    if (pfpSettings.overrideBackground) {
      uint numPixels = uint(width) * uint(height);
      // override default background with solid color
      for (uint i = 0; i < numPixels; ) {
        uint offset = i * 4;
        image[offset] = pfpSettings.backgroundColor[0];
        image[offset + 1] = pfpSettings.backgroundColor[1];
        image[offset + 2] = pfpSettings.backgroundColor[2];
        image[offset + 3] = 0xff;
        unchecked {
          ++i;
        }
      }
    } else {
      // copy default background
      for (uint i = 0; i < image.length; ) {
        image[i] = backgroundImage[i];
        unchecked {
          ++i;
        }
      }
    }
    return (image, width, height);
  }

  /// @dev kind of a hack but doesn't matter. seems like a one-off so just put it here
  function _drawNeckLine(bytes memory image) internal pure returns (bytes memory) {
    // the bottom of the head is an 8-pixel line representing the chinline/neck
    // by default, this is will be the "dark" color for that body color palette,
    // which is not black but rather a dark skin tone color.
    //
    // but if we are drawing just the head without the body, we actually want to have
    // the head outlined in black because that's the boundary shape.
    //
    // so we draw 8 black pixels over top of the "dark" pixels
    //
    // another design considered was uploading the "head" pattern separately to
    // the assets contract, for the same canvas, but on a "off" layer (11?) (body=10)
    // which fits with the intended design of how to use the assets contract
    //
    // but
    //
    // this was a one-off for now, so we are just doing the 8 pixel difference here

    // 8 pixels across

    // 1st pixel
    image[2864] = 0x00;
    image[2865] = 0x00;
    image[2866] = 0x00;
    image[2867] = 0xff;
    // 2nd pixel
    image[2868] = 0x00;
    image[2869] = 0x00;
    image[2870] = 0x00;
    image[2871] = 0xff;
    // 3rd pixel
    image[2872] = 0x00;
    image[2873] = 0x00;
    image[2874] = 0x00;
    image[2875] = 0xff;
    // 4th pixel
    image[2876] = 0x00;
    image[2877] = 0x00;
    image[2878] = 0x00;
    image[2879] = 0xff;
    // 5th pixel
    image[2880] = 0x00;
    image[2881] = 0x00;
    image[2882] = 0x00;
    image[2883] = 0xff;
    // 6th pixel
    image[2884] = 0x00;
    image[2885] = 0x00;
    image[2886] = 0x00;
    image[2887] = 0xff;
    // 7th pixel
    image[2888] = 0x00;
    image[2889] = 0x00;
    image[2890] = 0x00;
    // 8th pixel
    image[2891] = 0xff;
    image[2892] = 0x00;
    image[2893] = 0x00;
    image[2894] = 0x00;
    image[2895] = 0xff;
    return image;
  }

  /**
   * @dev Draw the layers of the avatar.
   * @param image The image to draw on.
   * @param mask The mask to apply before drawing.
   * @param canvasId The canvas ID to draw on.
   * @param dna The DNA to use.
   * @param pfpSettings The background settings to use.
   * @return The image with the layers drawn.
   */
  function _drawLayers(
    bytes memory image,
    bytes memory mask,
    uint8 canvasId,
    bytes32 dna,
    OpenAvatarProfilePictureSettings memory pfpSettings
  ) internal view returns (bytes memory) {
    // body
    uint8 bodyPattern = dna.bodyPattern();
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_BODY,
      bodyPattern,
      dna.bodyPalette()
    );

    // the neck is normally drawn on top of the body with a skin tone "neck"
    // but for this we want black border around the head not the body
    //
    // transparent bodies don't have a neck line
    if (pfpSettings.maskBelowTheNeck && bodyPattern != 0) {
      image = _drawNeckLine(image);
    }

    // tattoos
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_TATTOOS,
      dna.tattoosPattern(),
      dna.tattoosPalette()
    );
    // makeup
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_MAKEUP,
      dna.makeupPattern(),
      dna.makeupPalette()
    );
    // eyes
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_LEFT_EYE,
      dna.leftEyePattern(),
      dna.leftEyePalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_RIGHT_EYE,
      dna.rightEyePattern(),
      dna.rightEyePalette()
    );
    // clothes
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_BOTTOMWEAR,
      dna.bottomwearPattern(),
      dna.bottomwearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_FOOTWEAR,
      dna.footwearPattern(),
      dna.footwearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_TOPWEAR,
      dna.topwearPattern(),
      dna.topwearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_HANDWEAR,
      dna.handwearPattern(),
      dna.handwearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_OUTERWEAR,
      dna.outerwearPattern(),
      dna.outerwearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_JEWELRY,
      dna.jewelryPattern(),
      dna.jewelryPalette()
    );
    // facial hair - no mask
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawLayer(
      image,
      canvasId,
      LAYER_INDEX_FACIAL_HAIR,
      dna.facialHairPattern(),
      dna.facialHairPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_FACEWEAR,
      dna.facewearPattern(),
      dna.facewearPalette()
    );
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawMaskedLayer(
      image,
      mask,
      canvasId,
      LAYER_INDEX_EYEWEAR,
      dna.eyewearPattern(),
      dna.eyewearPalette()
    );
    // hair - no mask
    image = openAvatarGen0AssetsCanvasLayerCompositor.drawLayer(
      image,
      canvasId,
      LAYER_INDEX_HAIR,
      dna.hairPattern(),
      dna.hairPalette()
    );
    return image;
  }

  /**
   * @notice Render the given DNA as a base64-encoded SVG.
   * @param dna The DNA to render.
   * @return The base64-encoded SVG.
   */
  function renderBase64SVG(bytes32 dna) public view returns (bytes memory) {
    return renderBase64SVGWithSettings(dna, this.getProfilePictureSettings(dna));
  }

  /**
   * @notice Render the given DNA as a base64-encoded SVG.
   * @param dna The DNA to render.
   * @param pfpSettings The settings to use for the profile picture.
   * @return The base64-encoded SVG.
   */
  function renderBase64SVGWithSettings(
    bytes32 dna,
    OpenAvatarProfilePictureSettings memory pfpSettings
  ) public view returns (bytes memory) {
    (bytes memory image, uint8 width, uint8 height) = createBackgroundImage(pfpSettings);

    // copy mask into memory
    bytes memory mask = new bytes(openAvatarGen0AssetsRead.getCanvasNumPixels(canvasId));
    if (pfpSettings.maskBelowTheNeck) {
      uint length = mask.length;
      for (uint i = 0; i < length; ) {
        mask[i] = BELOW_THE_NECK_MASK[i];
        unchecked {
          ++i;
        }
      }
    }
    image = _drawLayers(image, mask, canvasId, dna, pfpSettings);
    return
      encodeBase64SVG(
        image,
        width,
        height,
        openAvatarGen0AssetsRead.hasAlphaChannel(),
        SVG_SCALE * width,
        SVG_SCALE * height
      );
  }
}
