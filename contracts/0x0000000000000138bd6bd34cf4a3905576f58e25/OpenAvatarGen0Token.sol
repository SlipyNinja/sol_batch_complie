// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {ERC721A, ERC721AQueryable, IERC721A} from 'erc721a/contracts/extensions/ERC721AQueryable.sol';
import {Base64} from './core/dependencies/Base64.sol';
import {AOpenAvatarMintStateMachine} from './core/erc721/AOpenAvatarMintStateMachine.sol';
import {Treasury} from './core/erc721/Treasury.sol';
import {ENSReverseClaimer} from './core/lib/ENSReverseClaimer.sol';
import {OpenAvatarGenerationZero} from './OpenAvatarGenerationZero.sol';
import {IOpenAvatarGen0RendererRegistry} from './IOpenAvatarGen0RendererRegistry.sol';
import {IOpenAvatarGen0Renderer} from './IOpenAvatarGen0Renderer.sol';
import {IOpenAvatarGen0Token, OpenAvatarGen0TokenMetadata} from './IOpenAvatarGen0Token.sol';

/**
 * @title OpenAvatarGen0Token
 * @author Cory Gabrielsen (cory.eth)
 *
 * @notice OpenAvatar is an onchain protocol for Avatars.
 * @dev This contract is the main entry point for the OpenAvatar protocol.
 *
 * ----------------------------------------------------------------------------
 * Generation 0
 * ----------------------------------------------------------------------------
 * This is OpenAvatar Generation 0.
 *
 *
 * ----------------------------------------------------------------------------
 * ERC-721
 * ----------------------------------------------------------------------------
 * OpenAvatarGen0Token is an ERC-721 token that represents an OpenAvatar.
 *
 *
 * ----------------------------------------------------------------------------
 * DNA
 * ----------------------------------------------------------------------------
 * *DNA* is a core building block of OpenAvatar.
 *
 * Every OpenAvatar is defined by a unique 32-byte DNA (gen 0). No two
 * OpenAvatars can have the same DNA.
 *
 * DNA is an extensible building block of OpenAvatar. Application-specific
 * re-interpretations of OpenAvatar DNA are entirely possible and encouraged.
 *
 * DNA determines how an OpenAvatar is rendered (gen 0). When users select how
 * their Avatar looks, they are by proxy choosing the Avatar's 32-byte DNA.
 *
 *
 * ----------------------------------------------------------------------------
 * Renderer
 * ----------------------------------------------------------------------------
 * A *Renderer* is a core building block of OpenAvatar.
 *
 * A render interface is defined, consisting of the following method:
 *   ```
 *   interface IOpenAvatarGen0Renderer {
 *       function renderURI(bytes32 dna) external view returns (string memory);
 *   }
 *   ```
 *
 *
 * ----------------------------------------------------------------------------
 * Text Records
 * ----------------------------------------------------------------------------
 * A *Text Record* is a core building block of OpenAvatar.
 *
 * Text records are key-value pairs of strings stored onchain by Avatar DNA
 * in the `OpenAvatarGen0TextRecords` contract. Token owners may store any
 * key/value pair for their token's DNA.
 *
 * This mechanism provides an onchain key/value data store for Avatar DNA.
 *
 * Text records may be used by other contracts and applications to read/write
 * arbitrary data to an OpenAvatar.
 *
 * For example, text records are used to determine if the token owner has
 * set the background color for their Profile Picture Renderer. This allows
 * token owners to dynamically customize their Avatar onchain, and provides
 * an example for more complex integrations.
 *
 *
 * ----------------------------------------------------------------------------
 * Renderer Registry
 * ----------------------------------------------------------------------------
 * A separate `OpenAvatarGen0RendererRegistry` contract is used to register
 * Renderers for use by the `OpenAvatarGen0Token` contract.
 *
 * The `OpenAvatarGen0Token` contract determines which Renderer to use for a
 * given token by delegating to the `OpenAvatarGen0RendererRegistry` contract.
 *
 * Default Renderer:
 * The registry maintains a concept of "default" Renderer, which may be
 * modified by the contract owner.
 *
 * Token Owners may optionally override the default Renderer for their token by
 * writing a valid 'gen0.renderer` text record to the
 * `OpenAvatarGen0TextRecords` contract.
 *
 * When the ERC721::tokenURI method is called, the Renderer (token default if
 * exists, otherwise registry default) is called to render the URI.
 *
 * The net effect is that rendering is invariant and onchain.
 *
 * If further Renderers are made available by the registry owner, token owners
 * may opt-in to those upgrades either in general (by not setting a token
 * default) or explicit choice (by setting their corresponding text record).
 *
 * This "soft-upgradeability" can be sunset by burning the registry fuse which
 * blocks further additions, thereby making the list of available Renderers
 * fully immutable.
 *
 * At launch, two Renderers are provided, described below.
 *
 *
 * ----------------------------------------------------------------------------
 * 'base' Renderer
 * ----------------------------------------------------------------------------
 * A base Renderer is provided with the key "base".
 *
 * The 'base' Renderer renders the Avatar with transparent background as a
 * forward-facing sprite.
 *
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
 */
contract OpenAvatarGen0Token is
  OpenAvatarGenerationZero,
  IOpenAvatarGen0Renderer,
  IOpenAvatarGen0Token,
  AOpenAvatarMintStateMachine,
  Treasury,
  ENSReverseClaimer,
  ERC721AQueryable
{
  using Strings for address;
  using Strings for uint256;

  /// @dev Event emitted when the fuse is burned for increasing the soft cap
  ///      supply
  event FuseBurnedCanIncreaseSupplySoftCap();
  /// @dev Event emitted when the fuse is burned for lowering the mint price
  event FuseBurnedCanLowerMintPrice();
  /// @dev Event emitted when the fuse is burned for raising the mint price
  event FuseBurnedCanRaiseMintPrice();
  /// @dev Event emitted when a new avatar is minted.
  event Mint(address to, bytes32 dna, uint tokenId);
  /// @dev Event emitted when the mint price is changed
  event MintPriceChange(uint oldPrice, uint newPrice);

  /// @dev Error when a component is already initialized.
  error AlreadyInitialized();
  /// @dev Revert error when the DNA does already minted.
  error DNAAlreadyMinted(bytes32 dna);
  /// @dev Revert error when the DNA does not exist.
  error DNADoesNotExist(bytes32 dna);
  /// @dev Event emitted when an interface is not supported.
  error InterfaceUnsupported(address contractAddress, bytes4 interfaceId);
  /// @dev Revert error when the batch size limit is exceeded.
  error MintBatchSizeLimitExceeded(uint batchSize);
  /// @dev Revert error when underpaid for a mint.
  error MintUnderpaid();
  /// @dev Revert error when not token owner for a permissioned action.
  error NotTokenOwner(uint tokenId);
  /// @dev Revert error when trying to batch mint the null DNA, which is not
  /// allowed.
  error NullDNARestrictedFromBatchMint(bytes32 dna);
  /// @dev Revert error when the supply cap is exceeded.
  error SupplyCapExceeded();
  /// @dev Revert error when the supply cap change would decrease the supply
  ///      cap.
  error SupplySoftCapChangeIsNotAnIncrease();
  /// @dev Revert error when the supply cap increase is not higher than the
  /// current supply cap.
  error SupplySoftCapIsMonotonicallyIncraesing();
  /// @dev Revert error when the supply cap change exceeds hard cap.
  error SupplySoftCapWouldExceedHardCap(uint newSupplyCap);
  /// @dev Revert error when token id does not exist.
  error TokenIdDoesNotExist(uint tokenId);

  /////////////////////////////////////////////////////////////////////////////
  // Dependencies
  /////////////////////////////////////////////////////////////////////////////
  /// @dev The ERC-165 interface id for the OpenAvatarGen0Renderer
  ///      (dependency).
  bytes4 private constant INTERFACE_ID_OPENAVATAR_GEN0_RENDERER_REGISTRY = 0x8646df82;

  /// @dev The IOpenAvatarGen0RendererRegistry dependency.
  IOpenAvatarGen0RendererRegistry public openAvatarGen0RendererRegistry;

  /////////////////////////////////////////////////////////////////////////////
  // Internal Data Structures
  /////////////////////////////////////////////////////////////////////////////

  // bidirectional mapping from token id <--> dna

  /// @dev One half of bi-directional mapping from DNA <-> token id.
  mapping(bytes32 dna => uint tokenId) private dnaToTokenId;
  /// @dev One half of bi-directional mapping from token id <-> DNA.
  mapping(uint tokenId => bytes32 dna) private tokenIdToDna;
  /// @dev track who minted each token
  mapping(bytes32 dna => address minter) private dnaToCreator;

  /////////////////////////////////////////////////////////////////////////////
  // Mint Supply
  /////////////////////////////////////////////////////////////////////////////

  /// @dev The maxium number of avatars.
  ///      Invariant: totalSupply() <= supplySoftCap() <= supplyHardCap()
  uint16 public constant MAX_SUPPLY = 16384;
  /// @dev The maxium number of avatars that can be minted in a single batch.
  uint8 public constant MAX_MINT_BATCH_SIZE_LIMIT = 20;

  /// @dev The total number of avatars that can be minted.
  ///      Invariant: totalSupply() <= supplySoftCap() <= supplyHardCap()
  uint16 public _supplySoftCap = 0;

  /////////////////////////////////////////////////////////////////////////////
  // Mint Price
  /////////////////////////////////////////////////////////////////////////////

  /// @dev The price to mint an avatar.
  uint public mintPrice;

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /// @dev Flag to indicate if the fuse has been burned for increasing the
  ///      supply cap
  bool public fuseBurnedCanIncreaseSupplySoftCap = false;
  /// @dev Flag to indicate if the fuse has been burned for lowering the mint
  ///      price
  bool public fuseBurnedCanLowerMintPrice = false;
  /// @dev Flag to indicate if the fuse has been burned for raising the mint
  ///      price
  bool public fuseBurnedCanRaiseMintPrice = false;

  /////////////////////////////////////////////////////////////////////////////
  // Constructor
  /////////////////////////////////////////////////////////////////////////////

  constructor(address ownerProxy) ERC721A('OpenAvatar', 'AVATR') {
    // will be deployed by ImmutableCreate2Factory and then transferred to the
    // configured owner.
    // using a proxy allows for using same constructor args and thus same
    // bytecode for all instances of this contract.

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
  function supportsInterface(
    bytes4 interfaceId
  ) public pure override(OpenAvatarGenerationZero, ERC721A, IERC721A) returns (bool) {
    return
      interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165.
      // ERC721
      interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721.
      interfaceId == 0x5b5e139f || // ERC165 interface ID for ERC721Metadata.
      // IOpenAvatarGen0Renderer
      interfaceId == 0xb93e4881 || // ERC165 interface ID for IOpenAvatarGen0Renderer.
      // IOpenAvatar
      interfaceId == 0xfdf02ac8 || // ERC165 interface ID for IOpenAvatarGeneration.
      interfaceId == 0x7b65147c || // ERC165 interface ID for IOpenAvatarSentinel.
      interfaceId == 0x86953eb4 || // ERC165 interface ID for IOpenAvatar.
      // IOpenAvatarGen0Token
      interfaceId == 0xc5f6fb61 || // ERC165 interface ID for IOpenAvatarGen0TokenMetadata.
      interfaceId == 0x2717336f || // ERC165 interface ID for IOpenAvatarGen0TokenDNA.
      interfaceId == 0x9840fe50 || // ERC165 interface ID for IOpenAvatarGen0Token.
      // IOpenAvatarGen0TokenMint
      interfaceId == 0x27fc9ea2 || // ERC165 interface ID for IOpenAvatarGen0TokenMintRead.
      interfaceId == 0x2f683360 || // ERC165 interface ID for IOpenAvatarGen0TokenMintWrite
      interfaceId == 0xf4a0a528 || // ERC165 interface ID for IOpenAvatarGen0TokenMintAdmin
      interfaceId == 0xfc3408ea; // ERC165 interface ID for IOpenAvatarGen0TokenMint.
  }

  /////////////////////////////////////////////////////////////////////////////
  // Initialize Dependencies
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @dev Initialize the contract.
   * @param openAvatarGen0RendererRegistry_ The address of the `OpenAvatarGen0RendererRegistry` contract.
   */
  function initialize(address openAvatarGen0RendererRegistry_) external onlyOwner {
    setOpenAvatarGen0RendererRegistry(openAvatarGen0RendererRegistry_);
  }

  /**
   * @notice Check if the contract has been initialized.
   * @return True if the contract has been initialized, false otherwise.
   */
  function isInitialized() external view returns (bool) {
    return address(openAvatarGen0RendererRegistry) != address(0);
  }

  /**
   * @notice Retrieves the address of the `OpenAvatarGen0RendererRegistry`
   * contract.
   *
   * The `OpenAvatarGen0RendererRegistry` contract is a registry that contains
   * references to all available renderers. A renderer is a contract that
   * takes avatar DNA and generates an image representation of the avatar.
   *
   * These renderers can be selected by token owners to customize the look
   * of their avatar, as specified in the 'gen0.renderer' field in the
   * `OpenAvatarGen0TextRecords` contract.
   *
   * Furthermore, the `OpenAvatarGen0RendererRegistry` contract can be
   * controlled by the registry owner, who can add new renderers or
   * permanently lock the list of registered renderers.
   *
   * @return The address of the `OpenAvatarGen0RendererRegistry` contract.
   */
  function getOpenAvatarGen0RendererRegistry() external view returns (address) {
    return address(openAvatarGen0RendererRegistry);
  }

  /**
   * @notice Set the OpenAvatarGen0RendererRegistry address.
   * @param openAvatarGen0RendererRegistry_ The address of the
   * OpenAvatarGen0RendererRegistry contract.
   * @dev This function can only be called once.
   */
  function setOpenAvatarGen0RendererRegistry(address openAvatarGen0RendererRegistry_) internal {
    // only set once
    if (address(openAvatarGen0RendererRegistry) != address(0)) revert AlreadyInitialized();

    // check ERC-165 support
    // only DNA interface is required
    if (!IERC165(openAvatarGen0RendererRegistry_).supportsInterface(INTERFACE_ID_OPENAVATAR_GEN0_RENDERER_REGISTRY)) {
      revert InterfaceUnsupported(openAvatarGen0RendererRegistry_, INTERFACE_ID_OPENAVATAR_GEN0_RENDERER_REGISTRY);
    }

    // set
    openAvatarGen0RendererRegistry = IOpenAvatarGen0RendererRegistry(openAvatarGen0RendererRegistry_);
  }

  /////////////////////////////////////////////////////////////////////////////
  // ERC721Metadata
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Generates and returns a base64 encoded JSON URI containing
   * metadata for a specified token ID.
   *
   * This URI encapsulates data such as the Generation of the avatar,
   * the DNA (unique identifier), the address of the OpenAvatarGen0Renderer
   * used to render the avatar, the ABI signature of the rendering function,
   * the token ID, and the owner of the token. It also includes an 'image'
   * field with a URI representing the avatar's image, and an 'attributes'
   * array containing trait metadata.
   *
   * @param tokenId The unique identifier of the token whose metadata to
   * retrieve.
   *
   * @return A base64 encoded JSON URI that contains metadata of the
   * given token ID.
   *
   * @dev This function will revert if the provided token ID has not
   * been minted yet.
   *
   * @dev The provided metadata extends the OpenAvatar URI to include
   * adherence to the OpenSea metadata standards.
   */
  function tokenURI(uint tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
    if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

    string memory generationZeroStr = OPENAVATAR_GENERATION_ZERO.toString();
    bytes32 dna = tokenIdToDna[tokenId];
    address mintedBy = dnaToCreator[dna];
    string memory mintedByStr = mintedBy.toHexString();
    address rendererAddress = openAvatarGen0RendererRegistry.getRendererByDNA(dna);
    string memory rendererAddressStr = rendererAddress.toHexString();
    string memory tokenIdStr = tokenId.toString();
    string memory dnaStr = uint(dna).toHexString(32);
    return
      string(
        abi.encodePacked(
          'data:application/json;base64,',
          Base64.encode(
            abi.encodePacked(
              '{"generation":',
              generationZeroStr,
              ',"dna":"',
              dnaStr,
              '","creator":"',
              dnaToCreator[dna].toHexString(),
              '","renderer":"',
              rendererAddressStr,
              '","renderer_abi":"renderURI(bytes32)","token_id":',
              tokenIdStr,
              ',"name":"OpenAvatar #',
              tokenIdStr,
              '","description":"OpenAvatar is an onchain protocol for Avatars.","image":"',
              IOpenAvatarGen0Renderer(rendererAddress).renderURI(dna),
              '","attributes":[{"trait_type":"Generation","value":',
              generationZeroStr,
              ',"display_type":"number"},{"trait_type":"DNA","value":"',
              dnaStr,
              '"},{"trait_type":"Creator","value":"',
              mintedByStr,
              '"},{"trait_type":"Renderer","value":"',
              rendererAddressStr,
              '"},{"trait_type":"Token ID","value":',
              tokenIdStr,
              ',"display_type":"number"}]}'
            )
          )
        )
      );
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarGen0Renderer
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice This function provides a render URI that represents the renderered
   * image for a specific avatar DNA. The `OpenAvatarGen0RendererRegistry`
   * contract manages a list of available renderers.
   *
   * The token owner can specify their preferred renderer from these
   * available options by setting the 'gen0.renderer' key in the
   * `OpenAvatarGen0TextRecords` contract to the renderer key. For example,
   *   ```
   *   openAvatarGen0TextRecords.setText(<dna>, 'gen0.renderer', 'base');
   *   ```
   * or,
   *   ```
   *   openAvatarGen0TextRecords.setText(<dna>, 'gen0.renderer', 'pfp');
   *   ```
   *
   * The registry owner may add more registries to become available
   * in the future, or the registry owner may burn a fuse to prevent
   * new renderes being added and permanently lock list of registered
   * renderers.
   *
   * This function, essentially, delegates the rendering task to the
   * `renderURI` function of the `OpenAvatarGen0Renderer` that matches the
   * given DNA. If no specific renderer is assigned to a token, it uses
   * the default renderer.
   *
   * @param dna The unique DNA of the avatar to render.
   * @return A base64 encoded URI that represents the rendered image
   * for the provided avatar DNA.
   *
   * @dev For a minted DNA, this function uses the assigned renderer or
   * the default renderer if none is set. For an un-minted DNA, it always
   * uses the default renderer.
   */
  function renderURI(bytes32 dna) external view returns (string memory) {
    return IOpenAvatarGen0Renderer(openAvatarGen0RendererRegistry.getRendererByDNA(dna)).renderURI(dna);
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarGen0TokenMetadata - An interface for the OpenAvatar metadata.
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns a base64-encoded JSON URI that encapsulates OpenAvatar
   * metadata for the given OpenAvatar DNA.
   *
   * The resulting URI includes the Generation of the avatar, the DNA
   * itself, the OpenAvatarGen0Renderer used to render the image of the avatar,
   * the ABI signature of the rendering function, the token ID associated
   * with the DNA, and the owner of that token.
   *
   * @param dna The unique DNA of the avatar whose metadata to retrieve.
   *
   * @return A base64 encoded URI representing the metadata of the given
   * avatar DNA.
   *
   * @dev This function will revert if the provided DNA has not been minted
   * into a token yet.
   */
  function openAvatarURI(bytes32 dna) external view returns (string memory) {
    uint tokenId = _getTokenIdByDNA(dna);
    string memory generationZeroStr = OPENAVATAR_GENERATION_ZERO.toString();
    address creatorAddress = dnaToCreator[dna];
    string memory creatorAddressStr = creatorAddress.toHexString();
    address rendererAddress = openAvatarGen0RendererRegistry.getRendererByDNA(dna);
    string memory rendererAddressStr = rendererAddress.toHexString();
    string memory tokenIdStr = tokenId.toString();
    string memory dnaStr = uint(dna).toHexString(32);
    return
      string(
        abi.encodePacked(
          'data:application/json;base64,',
          Base64.encode(
            abi.encodePacked(
              '{"generation":',
              generationZeroStr,
              ',"dna":"',
              dnaStr,
              '","creator":"',
              creatorAddressStr,
              '","renderer":"',
              rendererAddressStr,
              '","renderer_abi":"renderURI(bytes32)","token_id":',
              tokenIdStr,
              '}'
            )
          )
        )
      );
  }

  /**
   * @notice Retrieves OpenAvatar metadata associated with a specific token ID.
   *
   * The metadata encapsulates details such as the generation of the avatar,
   * the DNA, the chosen renderer for the avatar, the ABI signature of the
   * rendering function, the token ID itself, and the owner of the token.
   *
   * @param tokenId The unique identifier of the token to query.
   *
   * @return A `OpenAvatarGen0TokenMetadata` struct representing the metadata
   * associated with the token ID.
   *
   * @dev This function will revert if the provided token ID has not been
   * minted yet.
   */
  function _getOpenAvatarGen0TokenMetadataByTokenId(
    uint tokenId
  ) internal view returns (OpenAvatarGen0TokenMetadata memory) {
    if (!_exists(tokenId)) revert TokenIdDoesNotExist(tokenId);

    // struct OpenAvatarGen0TokenMetadata {
    //   uint generation;
    //   bytes32 dna;
    //   address renderer;
    //   uint tokenId;
    //   address owner;
    // }
    bytes32 dna = _getDNAByTokenId(tokenId);
    return
      OpenAvatarGen0TokenMetadata(
        OPENAVATAR_GENERATION_ZERO,
        tokenId,
        dna,
        dnaToCreator[dna],
        openAvatarGen0RendererRegistry.getRendererByDNA(dna)
      );
  }

  /**
   * @notice Retrieves OpenAvatar metadata associated with a specific DNA.
   *
   * The metadata encapsulates details such as the generation of the avatar,
   * the DNA itself, the chosen renderer for the avatar, the ABI signature of
   * the rendering function, the token ID, and the owner of the token.
   *
   * @param dna The unique DNA identifier of the avatar to query.
   *
   * @return A `OpenAvatarGen0TokenMetadata` struct representing the metadata
   * associated with the avatar's DNA.
   *
   * @dev This function will revert if the provided DNA has not been
   * minted into a token yet.
   */
  function getOpenAvatarGen0TokenMetadataByDNA(bytes32 dna) external view returns (OpenAvatarGen0TokenMetadata memory) {
    return _getOpenAvatarGen0TokenMetadataByTokenId(_getTokenIdByDNA(dna));
  }

  /**
   * @notice Retrieves OpenAvatar metadata associated with a specific token ID.
   *
   * The metadata encapsulates details such as the generation of the avatar,
   * the DNA, the chosen renderer for the avatar, the ABI signature of the
   * rendering function, the token ID itself, and the owner of the token.
   *
   * @param tokenId The unique identifier of the token to query.
   *
   * @return A `OpenAvatarGen0TokenMetadata` struct representing the metadata
   * associated with the token ID.
   *
   * @dev This function will revert if the provided token ID has not been
   * minted yet.
   */
  function getOpenAvatarGen0TokenMetadataByTokenId(
    uint tokenId
  ) external view returns (OpenAvatarGen0TokenMetadata memory) {
    return _getOpenAvatarGen0TokenMetadataByTokenId(tokenId);
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarGen0TokenDNA - An interface for the OpenAvatar DNA.
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Retrieves the DNA associated with a specific token ID.
   *
   * This function is a helper function to fetch the DNA for a given token ID.
   * The DNA serves as a unique identifier for each token, which can then be
   * used to retrieve other related information such as the token's metadata.
   *
   * @param tokenId The unique identifier of the token for which to retrieve
   * the DNA.
   *
   * @return The DNA represented as a bytes32 value associated with the token
   * ID.
   *
   * @dev This function will revert if the token ID provided has not been
   * minted yet.
   */
  function _getDNAByTokenId(uint tokenId) internal view returns (bytes32) {
    if (!_exists(tokenId)) revert TokenIdDoesNotExist(tokenId);

    return tokenIdToDna[tokenId];
  }

  /**
   * @notice Retrieves the DNA associated with a specific token ID for external
   * callers.
   *
   * @param tokenId The unique identifier of the token for which to retrieve
   * the DNA.
   *
   * @return The DNA represented as a bytes32 value associated with the token
   * ID.
   *
   * @dev This function will revert if the token ID provided has not been
   * minted yet.
   */
  function getDNAByTokenId(uint tokenId) external view returns (bytes32) {
    return _getDNAByTokenId(tokenId);
  }

  /**
   * @notice Retrieves the DNAs associated with an array of token IDs.
   *
   * This function accepts an array of token IDs and returns an array of DNAs
   * corresponding to those IDs.
   *
   * @param tokenIds An array of unique identifiers for which to retrieve the
   * DNAs.
   *
   * @return An array of DNAs represented as bytes32 values associated with the
   * token IDs.
   *
   * @dev This function will revert if any of the token IDs provided have not
   * been minted yet.
   */
  function getDNAsByTokenIds(uint[] calldata tokenIds) external view returns (bytes32[] memory) {
    uint length = tokenIds.length;
    bytes32[] memory dnas = new bytes32[](length);
    for (uint i = 0; i < length; ) {
      dnas[i] = _getDNAByTokenId(tokenIds[i]);
      unchecked {
        ++i;
      }
    }
    return dnas;
  }

  /**
   * @notice Retrieves the token ID associated with a specific DNA.
   *
   * This internal function takes a DNA value and returns the corresponding
   * token ID. If the DNA provided does not correspond to a minted token, the
   * function will revert
   *
   * @param dna The DNA for which to retrieve the token ID.
   *
   * @return The token ID associated with the provided DNA.
   *
   * @dev This function will revert if the DNA provided has not been minted
   * yet.
   */
  function _getTokenIdByDNA(bytes32 dna) internal view returns (uint) {
    uint tokenId = dnaToTokenId[dna];
    // defaults to 0 in which case we need to double check
    // that tokenId exists and matches provided dna
    // else it's just a consequence of 0 being default return
    if (tokenId == 0) {
      // Happy case  : tokenId exists, can return
      // Revert case : tokenId does not exist, revert
      //
      // We need to determine happy vs revert case
      //
      // CASE 1 (revert):
      //    tokenId == 0 && it doesn't exist
      //    --> revert (since not exists)
      //
      // CASE 2
      //    tokenId == 0 && it does exist
      //    => the 0 token has been minted
      //    => we need to disambiguate whether we got tokenId == 0
      //       because of the default return or because it's the 0 token
      //
      //    CASE A (happy):
      //            tokenIdToDna[tokenId] == dna
      //            => we got the 0 token
      //            => return tokenId (which is 0)
      //
      //    CASE B: (revert)
      //            tokenIdToDna[tokenId] != dna
      //            => we got the default return
      //            => revert (since not exists)
      //
      if (!_exists(tokenId) || tokenIdToDna[tokenId] != dna) {
        revert DNADoesNotExist(dna);
      }
    }
    return tokenId;
  }

  /**
   * @notice Retrieves the token ID associated with a specific DNA.
   *
   * @param dna The DNA for which to retrieve the token ID.
   *
   * @return The token ID associated with the provided DNA.
   *
   * @dev This function will revert if the DNA provided has not been minted
   * yet.
   */
  function getTokenIdByDNA(bytes32 dna) external view returns (uint) {
    return _getTokenIdByDNA(dna);
  }

  /**
   * @notice Retrieves the token IDs associated with an array of DNAs.
   *
   * This function accepts an array of DNAs and returns an array of token
   * IDs corresponding to those DNAs.
   *
   * @param dnas An array of DNAs for which to retrieve the token IDs.
   *
   * @return An array of token IDs associated with the provided DNAs.
   *
   * @dev This function will revert if any of the DNAs provided have not been
   * minted yet.
   */
  function getTokenIdsByDNAs(bytes32[] calldata dnas) external view returns (uint[] memory) {
    uint length = dnas.length;
    uint[] memory tokenIds = new uint[](length);
    for (uint i = 0; i < length; ) {
      tokenIds[i] = _getTokenIdByDNA(dnas[i]);
      unchecked {
        ++i;
      }
    }
    return tokenIds;
  }

  /**
   * @notice Retrieves the creator of a token.
   *
   * This function uses the DNA to identify the corresponding token and fetch
   * the creator of that token.
   *
   * @param tokenId The unique identifier of the token for which to retrieve
   * the DNA.
   *
   * @return The address of the creator of the token associated with the
   * provided token ID. If the token ID has not been minted yet, the zero
   * address is returned.
   */
  function creatorOf(uint tokenId) external view returns (address) {
    return dnaToCreator[_getDNAByTokenId(tokenId)];
  }

  /**
   * @notice Retrieves the creator of a token given its DNA.
   *
   * This function uses the DNA to identify the corresponding token and fetch
   * the creator of that token.
   *
   * @param dna The DNA of the token for which to retrieve the creator.
   *
   * @return The address of the creator of the token associated with the provided
   * DNA.
   *
   * @dev This function will revert if the DNA provided has not been minted
   * yet.
   */
  function creatorOfDNA(bytes32 dna) external view returns (address) {
    if (!_exists(_getTokenIdByDNA(dna))) revert DNADoesNotExist(dna);
    return dnaToCreator[dna];
  }

  /**
   * @notice Retrieves the owner of a token given its DNA.
   *
   * This function uses the DNA to identify the corresponding token and fetch
   * the owner of that token.
   *
   * @param dna The DNA of the token for which to retrieve the owner.
   *
   * @return The address of the owner of the token associated with the provided
   * DNA.

   * @dev This function will revert if the DNA provided has not been minted
   * yet.
   */
  function ownerOfDNA(bytes32 dna) external view returns (address) {
    return ownerOf(_getTokenIdByDNA(dna));
  }

  /**
   * @notice Retrieves the owners of tokens given an array of DNAs.
   *
   * This function accepts an array of DNAs and returns an array of owners
   * corresponding to those DNAs.
   *
   * @param dnas An array of DNAs for which to retrieve the owners.
   *
   * @return An array of addresses representing the owners of the tokens
   * associated with the provided DNAs.
   *
   * @dev This function will revert if any of the DNAs provided have not been
   * minted yet.
   */
  function ownerOfDNAs(bytes32[] calldata dnas) external view returns (address[] memory) {
    uint length = dnas.length;
    address[] memory owners = new address[](length);
    for (uint i = 0; i < length; i++) {
      owners[i] = ownerOf(_getTokenIdByDNA(dnas[i]));
    }
    return owners;
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarMintRead - An interface for reading OpenAvatar minting state.
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Checks if the specified DNA has been associated with a token
   * (minted).
   * @param dna The DNA string to be checked.
   * @return Returns true if the DNA has been minted, false otherwise.
   */
  function isMinted(bytes32 dna) external view returns (bool) {
    uint tokenId = dnaToTokenId[dna];
    if (tokenId > 0) {
      // if the token id is > 0, then the dna has been minted
      // we don't need to check _exists because this mapping is
      // only set when the token is minted
      // (but it's not trivial because of the way batch mint
      //  has to check this data structure first)
      return true;
    }

    // we need to double check that the token id exists and matches the
    // provided dna
    bytes32 dnaFromTokenId = tokenIdToDna[tokenId];
    // if the dna from the token id does not match the provided dna
    // then the dna has not been minted
    if (dnaFromTokenId != dna) return false;

    // if they are both zero, then the dna has not been minted
    // except in one exceptional case:
    //    an invalid batch mint of [DNA=0, DNA=0] as the first two tokens

    // otherwise, the dna has been minted
    return _exists(tokenId);
  }

  /**
   * @notice Checks the mint status for each DNA in the provided list.
   * @param dnas An array of DNA strings to be checked.
   * @return An array of booleans indicating the mint status for each DNA. A
   * true value at index i indicates that dnas[i] has been minted.
   */
  function isMintedEach(bytes32[] calldata dnas) external view returns (bool[] memory) {
    uint length = dnas.length;
    bool[] memory minted = new bool[](length);
    for (uint i = 0; i < length; ) {
      minted[i] = this.isMinted(dnas[i]);
      unchecked {
        ++i;
      }
    }
    return minted;
  }

  /**
   * @notice Retrieves the current price required to mint a new token via the
   * mint function.
   * @return The current price in wei for minting a new token.
   */
  function getMintPrice() external view returns (uint) {
    return mintPrice;
  }

  /**
   * @notice Retrieves the "soft cap" token mint quantity. This number is
   * tokens tha can be minted. This number is mutable and can increase up
   * to the hard cap.
   * Invariant: totalSupply() <= supplySoftCap() <= supplyHardCap().
   * @return Maximum quantity of tokens mintable.
   */
  function supplySoftCap() external view returns (uint16) {
    return _supplySoftCap;
  }

  /**
   * @notice increases the soft cap supply. This number is mutable and can
   * increase up to the hard cap. Invariant: totalSupply() <= supplySoftCap()
   * <= supplyHardCap().
   * @param amount The new soft cap supply.
   */
  function increaseSupplySoftCap(uint16 amount) external onlyOwner {
    if (fuseBurnedCanIncreaseSupplySoftCap) revert OperationBlockedByBurnedFuse();
    if (amount <= _supplySoftCap) revert SupplySoftCapChangeIsNotAnIncrease();
    if (amount > MAX_SUPPLY) revert SupplySoftCapWouldExceedHardCap(amount);
    _supplySoftCap = amount;
  }

  /**
   * @notice Retrieves the maximum token mint quantity. This number is immutable
   * and can never change. The number of tokens minted can never exceed this
   * number. Invariant: totalSupply() <= supplySoftCap() <= supplyHardCap().
   * @return Maximum quantity of tokens mintable.
   */
  function supplyHardCap() external pure returns (uint16) {
    return MAX_SUPPLY;
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarMint - An interface allowing the mint price to be updated.
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Sets the price to mint a new token using the mint function.
   * @param val The new price to mint a new token using the mint function.
   * @dev Only callable by the owner.
   */
  function setMintPrice(uint val) external onlyOwner {
    if (val > mintPrice && fuseBurnedCanRaiseMintPrice) revert OperationBlockedByBurnedFuse();
    if (val < mintPrice && fuseBurnedCanLowerMintPrice) revert OperationBlockedByBurnedFuse();
    if (mintPrice == val) return;
    uint oldPrice = mintPrice;
    mintPrice = val;
    emit MintPriceChange(oldPrice, val);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Fuses
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Check if fuse for increasing soft cap supply.
   * @return True if fuse is burned, false otherwise.
   */
  function isFuseBurnedCanIncreaseSupplySoftCap() external view returns (bool) {
    return fuseBurnedCanIncreaseSupplySoftCap;
  }

  /**
   * @notice Burns the fuse that prohibits increasing the soft cap supply.
   * @dev Executable only by owner. No effect if fuse is already burned.
   */
  function burnFuseCanIncreaseSupplySoftCap() external onlyOwner {
    if (fuseBurnedCanIncreaseSupplySoftCap) return;
    fuseBurnedCanIncreaseSupplySoftCap = true;
    emit FuseBurnedCanIncreaseSupplySoftCap();
  }

  /**
   * @notice Check if fuse for lowering mint price is burned.
   * @return True if fuse is burned, false otherwise.
   */
  function isFuseBurnedCanLowerMintPrice() external view returns (bool) {
    return fuseBurnedCanLowerMintPrice;
  }

  /**
   * @notice Burns the fuse that prohibits decreasing the mint price.
   * @dev Executable only by owner. No effect if fuse is already burned.
   */
  function burnFuseCanLowerMintPrice() external onlyOwner {
    if (fuseBurnedCanLowerMintPrice) return;
    fuseBurnedCanLowerMintPrice = true;
    emit FuseBurnedCanLowerMintPrice();
  }

  /**
   * @notice Check if fuse for raising mint price is burned.
   * @return True if fuse is burned, false otherwise.
   */
  function isFuseBurnedCanRaiseMintPrice() external view returns (bool) {
    return fuseBurnedCanRaiseMintPrice;
  }

  /**
   * @notice Burns the fuse that prohibits increasing the mint price.
   * @dev Executable only by owner. No effect if fuse is already burned.
   */
  function burnFuseCanRaiseMintPrice() external onlyOwner {
    if (fuseBurnedCanRaiseMintPrice) return;
    fuseBurnedCanRaiseMintPrice = true;
    emit FuseBurnedCanRaiseMintPrice();
  }

  /////////////////////////////////////////////////////////////////////////////
  // IOpenAvatarMintWrite - An interface for minting OpenAvatars.
  /////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Mints a token for a given address.
   * @param to The recipient of the minted token.
   * @param dna The dna of the minted token.
   */
  function _mintTo(address to, bytes32 dna) internal {
    // ensure dna is not already used
    if (this.isMinted(dna)) revert DNAAlreadyMinted(dna);

    // 0-indexed token id
    uint tokenId = totalSupply();

    // ensure its not bigger than max supply
    if (tokenId < _supplySoftCap) {
      tokenIdToDna[tokenId] = dna;
      dnaToTokenId[dna] = tokenId;
      dnaToCreator[dna] = to;

      // mint
      _safeMint(to, 1);

      // emit event
      emit Mint(to, dna, tokenId);
    } else {
      revert SupplyCapExceeded();
    }
  }

  /**
   * @notice Mints a token.
   * @param dna The dna of the minted token.
   * @dev Only callable if mint is public.
   */
  function mint(bytes32 dna) external payable onlyAuthorizedMint {
    if (msg.value < mintPrice) revert MintUnderpaid();
    // mint to the immediate caller, either EOA or contract
    _mintTo(msg.sender, dna);
  }

  /**
   * @notice Mints a token for a given address.
   * @param to The recipient of the minted token.
   * @param dna The dna of the minted token.
   * @dev Only callable if mint is public.
   */
  function mintTo(address to, bytes32 dna) external payable onlyAuthorizedMint {
    if (msg.value < mintPrice) revert MintUnderpaid();
    // mint to provided address
    _mintTo(to, dna);
  }

  /**
   * @notice Mints a batch of tokens for a given address.
   * @param to The recipient of the minted tokens.
   * @param dnas The dnas of the minted tokens.
   */
  function _mintBatchTo(address to, bytes32[] calldata dnas) internal {
    uint totalSupply = totalSupply();
    uint n = dnas.length;
    if (n == 0) return; // no-op
    if (n > MAX_MINT_BATCH_SIZE_LIMIT) revert MintBatchSizeLimitExceeded(n);

    if (totalSupply + n - 1 < _supplySoftCap) {
      for (uint i; i < n; ) {
        bytes32 dna = dnas[i];

        // don't allow batch minting of the null DNA
        // else we might end up with multiple tokens with the same DNA
        // because the way the mapping checks work in the isMinted function
        // we cannot distinguish between a DNA with tokenId=0 and a DNA that
        // has not been minted
        //
        // so ultimately this primarily prevents a bug of calling
        // mintBatch([0, 0, ...]) before mint(0) has been called
        //
        // for prod, call mint(0) before public mint opens then this can be
        // removed for gas optimization since isMinted will return true for
        // null DNA
        if (dna == 0) revert NullDNARestrictedFromBatchMint(dna);

        // ensure dna is not already used
        if (this.isMinted(dna)) revert DNAAlreadyMinted(dna);

        // 0-indexed token id
        uint tokenId = totalSupply + i;

        tokenIdToDna[tokenId] = dna;
        dnaToTokenId[dna] = tokenId;
        dnaToCreator[dna] = to;

        // emit event
        emit Mint(to, dna, tokenId);

        unchecked {
          ++i;
        }
      }

      // mint all as one batch
      _safeMint(to, n);
    } else {
      revert SupplyCapExceeded();
    }
  }

  /**
   * @notice Mints a batch of tokens.
   * @param dnas The dnas of the minted tokens.
   * @dev Only callable if mint is public.
   */
  function mintBatch(bytes32[] calldata dnas) external payable onlyAuthorizedMint {
    if (msg.value < mintPrice * dnas.length) revert MintUnderpaid();
    // mint to the immediate caller, either EOA or contract
    _mintBatchTo(msg.sender, dnas);
  }

  /**
   * @notice Mints a batch of tokens for a given address.
   * @param to The recipient of the minted tokens.
   * @param dnas The dnas of the minted tokens.
   * @dev Only callable if mint is public.
   */
  function mintBatchTo(address to, bytes32[] calldata dnas) external payable onlyAuthorizedMint {
    if (msg.value < mintPrice * dnas.length) revert MintUnderpaid();
    // mint to the provided address
    _mintBatchTo(to, dnas);
  }
}
