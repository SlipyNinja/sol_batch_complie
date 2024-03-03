// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICryptoPunksData} from "../interfaces/ICryptoPunksData.sol";
import {json} from "sol-json/json.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/**
 * @title  CryptoPunksWrappedMetadata
 * @author Modified from James Wenzel (emo.eth) (https://github.com/emo-eth/wrapped-punks/blob/main/src/PunksWrapperMetadata.sol)
 * @notice Abstract contract to fetch and format metadata for wrapped Punks.
 */
abstract contract CryptoPunks721Metadata {
    ICryptoPunksData public immutable PUNKS_DATA;

    constructor(address _punksData) {
        PUNKS_DATA = ICryptoPunksData(_punksData);
    }

    string private constant _BACKGROUND_FILL = '<rect width="100%" height="100%" fill="#66A670"/>';

    /**
     * @dev Returns the string URI for a given token ID.
     * @param tokenId The index of the punk to get the URI for
     */
    function stringURI(uint256 tokenId) internal view returns (string memory) {
        uint16 punkIndex = uint16(tokenId);
        string memory imageData = PUNKS_DATA.punkImageSvg(punkIndex);
        imageData = LibString.slice(imageData, 24);

        imageData = LibString.concat(
            LibString.slice(imageData, 0, 74), LibString.concat(_BACKGROUND_FILL, LibString.slice(imageData, 74))
        );

        string memory attributes = PUNKS_DATA.punkAttributes(punkIndex);

        attributes = parseAttributesArray(attributes);
        return json.object(
            string.concat(
                json.property("image", string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(imageData)))),
                ",",
                json.rawProperty("attributes", attributes)
            )
        );
    }

    /**
     * @dev Parse a comma-separated list of attributes into a JSON array of attributes. Also calculates and appends an
     *      "Attribute Count" attribute.
     * @param attributes The attributes string to parse
     */
    function parseAttributesArray(string memory attributes) internal pure returns (string memory parsed) {
        string[] memory individualTraits = LibString.split(attributes, string(", "));
        bytes1 firstChar = bytes(individualTraits[0])[0];
        // only humans have skin tones, and their "type" always starts with M or F
        bool isHuman = firstChar == "M" || firstChar == "F";
        string[] memory attributesArray;
        // placeholder if human
        string[] memory typeAndSkinToneIfHuman;
        if (isHuman) {
            // include an extra attribute for "Attribute Count" and an extra for "Skin Tone"
            attributesArray = new string[](individualTraits.length + 2);
            typeAndSkinToneIfHuman = LibString.split(individualTraits[0], " ");
            attributesArray[0] = createAttribute("Type", typeAndSkinToneIfHuman[0]);
        } else {
            attributesArray = new string[](individualTraits.length + 1);
            attributesArray[0] = createAttribute("Type", individualTraits[0]);
        }
        // "type" is not traditionally counted in the attribute count, nor is skin tone
        uint256 count = individualTraits.length - 1;

        // cryptopunks website refers to remaining attributes just as "Attributes" (versus OpenSea's "Accessories")
        string memory trait = "Attribute";
        // start at 1 to skip "Type"; iterate over remaining attributes, if any
        for (uint256 i = 1; i < individualTraits.length; i++) {
            attributesArray[i] = createAttribute(trait, individualTraits[i]);
        }

        // add "Attribute Count" meta-attribute
        attributesArray[individualTraits.length] = createAttribute("Attribute Count", LibString.toString(count));

        if (isHuman) {
            // add "Skin Tone" meta-attribute
            attributesArray[individualTraits.length + 1] = createAttribute("Skin Tone", typeAndSkinToneIfHuman[1]);
        }

        // concat all attributes into a single JSON array
        return json.arrayOf(attributesArray);
    }

    /**
     * @dev Create a single attribute JSON object.
     */
    function createAttribute(string memory trait, string memory value) internal pure returns (string memory) {
        return json.object(string.concat(json.property("trait_type", trait), ",", json.property("value", value)));
    }
}
