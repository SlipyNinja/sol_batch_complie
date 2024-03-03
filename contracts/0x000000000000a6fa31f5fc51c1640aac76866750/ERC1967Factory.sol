// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Factory for deploying and managing ERC1967 proxy contracts.
/// @author Yuga Labs
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/ERC1967Factory.sol)
contract ERC1967Factory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The proxy deployment failed.
    error DeploymentFailed();

    /// @dev The upgrade failed.
    error UpgradeFailed();

    /// @dev `bytes4(keccak256(bytes("DeploymentFailed()")))`.
    uint256 internal constant _DEPLOYMENT_FAILED_ERROR_SELECTOR = 0x30116425;

    /// @dev `bytes4(keccak256(bytes("UpgradeFailed()")))`.
    uint256 internal constant _UPGRADE_FAILED_ERROR_SELECTOR = 0x55299b49;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The implementation for a proxy has been upgraded.
    event Upgraded(address indexed proxy, address indexed implementation);

    /// @dev A proxy has been deployed.
    event Deployed(address indexed proxy, address indexed implementation);

    /// @dev `keccak256(bytes("Upgraded(address,address)"))`.
    uint256 internal constant _UPGRADED_EVENT_SIGNATURE =
        0x5d611f318680d00598bb735d61bacf0c514c6b50e1e5ad30040a4df2b12791c7;

    /// @dev `keccak256(bytes("Deployed(address,address)"))`.
    uint256 internal constant _DEPLOYED_EVENT_SIGNATURE =
        0x09e48df7857bd0c1e0d31bb8a85d42cf1874817895f171c917f6ee2cea73ec20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    uint256 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     UPGRADE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Upgrades the proxy to point to `implementation`.
    /// Then, calls the proxy with abi encoded `data`.
    function _upgrade(address proxy, address implementation, bytes calldata data) internal {
        assembly {
            // Set up the calldata to upgrade the proxy.
            let m := mload(0x40)
            mstore(m, implementation)
            mstore(add(m, 0x20), _IMPLEMENTATION_SLOT)
            calldatacopy(add(m, 0x40), data.offset, data.length)
            // Try upgrading the proxy and revert upon failure.
            if iszero(call(gas(), proxy, callvalue(), m, add(0x40, data.length), 0x00, 0x00)) {
                // Revert with the `UpgradeFailed` selector if there is no error returndata.
                if iszero(returndatasize()) {
                    mstore(0x00, _UPGRADE_FAILED_ERROR_SELECTOR)
                    revert(0x1c, 0x04)
                }
                // Otherwise, bubble up the returned error.
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
            // Emit the {Upgraded} event.
            log3(0, 0, _UPGRADED_EVENT_SIGNATURE, proxy, implementation)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      DEPLOY FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys the proxy deterministically with a `salt`.
    function _deploy(address implementation, bytes32 salt, bytes memory data) internal returns (address proxy) {
        bytes32 m = _initCode();
        assembly {
            // Create the proxy.
            proxy := create2(0, add(m, 0x13), 0x88, salt)
            // Revert if the creation fails.
            if iszero(proxy) {
                mstore(0x00, _DEPLOYMENT_FAILED_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }

            // Set up the calldata to set the implementation of the proxy.
            mstore(m, implementation)
            mstore(add(m, 0x20), _IMPLEMENTATION_SLOT)
            let dataLength := mload(data) // Load the length of the data

            let dataPtr := add(data, 0x20) // Skip the length field of the `data`.
            let mPtr := add(m, 0x40) // Start copying to this position in memory.
            for { let end := add(dataPtr, dataLength) } lt(dataPtr, end) { dataPtr := add(dataPtr, 0x20) } {
                mstore(mPtr, mload(dataPtr))
                mPtr := add(mPtr, 0x20)
            }

            // Try setting the implementation on the proxy and revert upon failure.
            if iszero(call(gas(), proxy, callvalue(), m, add(0x40, dataLength), 0x00, 0x00)) {
                // Revert with the `DeploymentFailed` selector if there is no error returndata.
                if iszero(returndatasize()) {
                    mstore(0x00, _DEPLOYMENT_FAILED_ERROR_SELECTOR)
                    revert(0x1c, 0x04)
                }
                // Otherwise, bubble up the returned error.
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }

            // Emit the {Deployed} event.
            log3(0, 0, _DEPLOYED_EVENT_SIGNATURE, proxy, implementation)
        }
    }

    /// @dev Returns the address of the proxy deployed with `salt`.
    function _predictDeterministicAddress(bytes32 salt) internal view returns (address predicted) {
        bytes32 hash = _initCodeHash();
        assembly {
            // Compute and store the bytecode hash.
            mstore8(0x00, 0xff) // Write the prefix.
            mstore(0x35, hash)
            mstore(0x01, shl(96, address()))
            mstore(0x15, salt)
            // Note: `predicted` has dirty upper 96 bits. We won't clean it here
            // as it will be automatically cleaned when it is copied into the returndata.
            // Please clean as needed if used in other inline assembly blocks.
            predicted := keccak256(0x00, 0x55)
            // Restore the part of the free memory pointer that has been overwritten.
            mstore(0x35, 0)
        }
    }

    /// @dev Returns the initialization code hash of the proxy.
    /// Used for mining vanity addresses with create2crunch.
    function _initCodeHash() internal view returns (bytes32 result) {
        bytes32 m = _initCode();
        assembly {
            result := keccak256(add(m, 0x13), 0x88)
        }
    }

    /// @dev Returns a pointer to the initialization code of a proxy created via this factory.
    function _initCode() internal view returns (bytes32 m) {
        assembly {
            /**
             * -------------------------------------------------------------------------------------+
             * CREATION (9 bytes)                                                                   |
             * -------------------------------------------------------------------------------------|
             * Opcode     | Mnemonic        | Stack               | Memory                          |
             * -------------------------------------------------------------------------------------|
             * 60 runSize | PUSH1 runSize   | r                   |                                 |
             * 3d         | RETURNDATASIZE  | 0 r                 |                                 |
             * 81         | DUP2            | r 0 r               |                                 |
             * 60 offset  | PUSH1 offset    | o r 0 r             |                                 |
             * 3d         | RETURNDATASIZE  | 0 o r 0 r           |                                 |
             * 39         | CODECOPY        | 0 r                 | [0..runSize): runtime code      |
             * f3         | RETURN          |                     | [0..runSize): runtime code      |
             * -------------------------------------------------------------------------------------|
             * RUNTIME (127 bytes)                                                                  |
             * -------------------------------------------------------------------------------------|
             * Opcode      | Mnemonic       | Stack               | Memory                          |
             * -------------------------------------------------------------------------------------|
             *                                                                                      |
             * ::: keep some values in stack :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | 0                   |                                 |
             * 3d          | RETURNDATASIZE | 0 0                 |                                 |
             *                                                                                      |
             * ::: check if caller is factory ::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 33          | CALLER         | c 0 0               |                                 |
             * 73 factory  | PUSH20 factory | f c 0 0             |                                 |
             * 14          | EQ             | isf 0 0             |                                 |
             * 60 0x57     | PUSH1 0x57     | dest isf 0 0        |                                 |
             * 57          | JUMPI          | 0 0                 |                                 |
             *                                                                                      |
             * ::: copy calldata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 36          | CALLDATASIZE   | cds 0 0             |                                 |
             * 3d          | RETURNDATASIZE | 0 cds 0 0           |                                 |
             * 3d          | RETURNDATASIZE | 0 0 cds 0 0         |                                 |
             * 37          | CALLDATACOPY   | 0 0                 | [0..calldatasize): calldata     |
             *                                                                                      |
             * ::: delegatecall to implementation ::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 36          | CALLDATASIZE   | cds 0 0             | [0..calldatasize): calldata     |
             * 3d          | RETURNDATASIZE | 0 cds 0 0           | [0..calldatasize): calldata     |
             * 7f slot     | PUSH32 slot    | s 0 cds 0 0         | [0..calldatasize): calldata     |
             * 54          | SLOAD          | i 0 cds 0 0         | [0..calldatasize): calldata     |
             * 5a          | GAS            | g i 0 cds 0 0       | [0..calldatasize): calldata     |
             * f4          | DELEGATECALL   | succ                | [0..calldatasize): calldata     |
             *                                                                                      |
             * ::: copy returndata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | rds succ            | [0..calldatasize): calldata     |
             * 60 0x00     | PUSH1 0x00     | 0 rds succ          | [0..calldatasize): calldata     |
             * 80          | DUP1           | 0 0 rds succ        | [0..calldatasize): calldata     |
             * 3e          | RETURNDATACOPY | succ                | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: branch on delegatecall status :::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 60 0x52     | PUSH1 0x52     | dest succ           | [0..returndatasize): returndata |
             * 57          | JUMPI          |                     | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: delegatecall failed, revert :::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
             * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
             * fd          | REVERT         |                     | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: delegatecall succeeded, return ::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 5b          | JUMPDEST       |                     | [0..returndatasize): returndata |
             * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
             * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
             * f3          | RETURN         |                     | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: set new implementation (caller is factory) ::::::::::::::::::::::::::::::::::::: |
             * 5b          | JUMPDEST       | 0 0                 |                                 |
             * 3d          | RETURNDATASIZE | 0 0 0               |                                 |
             * 35          | CALLDATALOAD   | impl 0 0            |                                 |
             * 06 0x20     | PUSH1 0x20     | w impl 0 0          |                                 |
             * 35          | CALLDATALOAD   | slot impl 0 0       |                                 |
             * 55          | SSTORE         | 0 0                 |                                 |
             *                                                                                      |
             * ::: no extra calldata, return :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 60 0x40     | PUSH1 0x40     | 2w 0 0              |                                 |
             * 80          | DUP1           | 2w 2w 0 0           |                                 |
             * 36          | CALLDATASIZE   | cds 2w 2w 0 0       |                                 |
             * 11          | GT             | gt 2w 0 0           |                                 |
             * 15          | ISZERO         | lte 2w 0 0          |                                 |
             * 60 0x52     | PUSH1 0x52     | dest lte 2w 0 0     |                                 |
             * 57          | JUMPI          | 2w 0 0              |                                 |
             *                                                                                      |
             * ::: copy extra calldata to memory :::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 36          | CALLDATASIZE   | cds 2w 0 0          |                                 |
             * 03          | SUB            | t 0 0               |                                 |
             * 80          | DUP1           | t t 0 0             |                                 |
             * 60 0x40     | PUSH1 0x40     | 2w t t 0 0          |                                 |
             * 3d          | RETURNDATASIZE | 0 2w t t 0 0        |                                 |
             * 37          | CALLDATACOPY   | t 0 0               | [0..t): extra calldata          |
             *                                                                                      |
             * ::: delegatecall to implementation ::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | 0 t 0 0             | [0..t): extra calldata          |
             * 3d          | RETURNDATASIZE | 0 0 t 0 0           | [0..t): extra calldata          |
             * 35          | CALLDATALOAD   | i 0 t 0 0           | [0..t): extra calldata          |
             * 5a          | GAS            | g i 0 t 0 0         | [0..t): extra calldata          |
             * f4          | DELEGATECALL   | succ                | [0..t): extra calldata          |
             *                                                                                      |
             * ::: copy returndata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | rds succ            | [0..t): extra calldata          |
             * 60 0x00     | PUSH1 0x00     | 0 rds succ          | [0..t): extra calldata          |
             * 80          | DUP1           | 0 0 rds succ        | [0..t): extra calldata          |
             * 3e          | RETURNDATACOPY | succ                | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: branch on delegatecall status :::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 60 0x52     | PUSH1 0x52     | dest succ           | [0..returndatasize): returndata |
             * 57          | JUMPI          |                     | [0..returndatasize): returndata |
             *                                                                                      |
             * ::: delegatecall failed, revert :::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
             * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
             * fd          | REVERT         |                     | [0..returndatasize): returndata |
             * -------------------------------------------------------------------------------------+
             */

            m := mload(0x40)
            // forgefmt: disable-start
            switch shr(112, address())
            case 0 {
                // If the factory's address has six or more leading zero bytes.
                mstore(add(m, 0x75), 0x604c573d6000fd) // 7
                mstore(add(m, 0x6e), 0x3d3560203555604080361115604c5736038060403d373d3d355af43d6000803e) // 32
                mstore(add(m, 0x4e), 0x3735a920a3ca505d382bbc545af43d6000803e604c573d6000fd5b3d6000f35b) // 32
                mstore(add(m, 0x2e), 0x14605157363d3d37363d7f360894a13ba1a3210667c828492db98dca3e2076cc) // 32
                mstore(add(m, 0x0e), address()) // 14
                mstore(m, 0x60793d8160093d39f33d3d336d) // 9 + 4
            }
            default {
                mstore(add(m, 0x7b), 0x6052573d6000fd) // 7
                mstore(add(m, 0x74), 0x3d356020355560408036111560525736038060403d373d3d355af43d6000803e) // 32
                mstore(add(m, 0x54), 0x3735a920a3ca505d382bbc545af43d6000803e6052573d6000fd5b3d6000f35b) // 32
                mstore(add(m, 0x34), 0x14605757363d3d37363d7f360894a13ba1a3210667c828492db98dca3e2076cc) // 32
                mstore(add(m, 0x14), address()) // 20
                mstore(m, 0x607f3d8160093d39f33d3d3373) // 9 + 4
            }
            // forgefmt: disable-end
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          HELPERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to return an empty bytes calldata.
    function _emptyData() internal pure returns (bytes calldata data) {
        assembly {
            data.length := 0
        }
    }
}
