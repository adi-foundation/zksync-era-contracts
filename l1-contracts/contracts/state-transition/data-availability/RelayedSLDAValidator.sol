// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

// solhint-disable gas-custom-errors, reason-string

import {IL1DAValidator, L1DAValidatorOutput, PubdataSource} from "../chain-interfaces/IL1DAValidator.sol";
import {IL1Messenger} from "../../common/interfaces/IL1Messenger.sol";

import {CalldataDA} from "./CalldataDA.sol";

import {L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR} from "../../common/L2ContractAddresses.sol";

/// @notice The DA validator intended to be used in Era-environment.
/// @dev For compaitbility reasons it accepts calldata in the same format as the `RollupL1DAValidator`, but unlike the latter it
/// does not support blobs.
/// @dev Note that it does not provide any compression whatsoever.
contract RelayedSLDAValidator is IL1DAValidator, CalldataDA {
    /// @inheritdoc IL1DAValidator
    function checkDA(
        uint256 _chainId,
        bytes32 _l2DAValidatorOutputHash,
        bytes calldata _operatorDAInput,
        uint256 _maxBlobsSupported
    ) external returns (L1DAValidatorOutput memory output) {
        // Preventing "stack too deep" error
        uint256 blobsProvided;
        bytes32 fullPubdataHash;
        bytes calldata l1DaInput;
        {
            bytes32 stateDiffHash;
            bytes32[] memory blobsLinearHashes;
            (
                stateDiffHash,
                fullPubdataHash,
                blobsLinearHashes,
                blobsProvided,
                l1DaInput
            ) = _processL2RollupDAValidatorOutputHash(_l2DAValidatorOutputHash, _maxBlobsSupported, _operatorDAInput);

            output.stateDiffHash = stateDiffHash;
            output.blobsLinearHashes = blobsLinearHashes;
        }

        uint8 pubdataSource = uint8(l1DaInput[0]);

        // Note, that the blobs are not supported in the RelayedSLDAValidator.
        if (pubdataSource == uint8(PubdataSource.Calldata)) {
            bytes calldata pubdata;
            bytes32[] memory blobCommitments;

            (blobCommitments, pubdata) = _processCalldataDA(
                blobsProvided,
                fullPubdataHash,
                _maxBlobsSupported,
                l1DaInput[1:]
            );

            // Re-sending all the pubdata in pure form to L1.
            // slither-disable-next-line unused-return
            IL1Messenger(L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR).sendToL1(abi.encode(_chainId, pubdata));

            output.blobsOpeningCommitments = blobCommitments;
        } else {
            revert("l1-da-validator/invalid-pubdata-source");
        }

        // We verify that for each set of blobHash/blobCommitment are either both empty
        // or there are values for both.
        // This is mostly a sanity check and it is not strictly required.
        for (uint256 i = 0; i < _maxBlobsSupported; ++i) {
            require(
                (output.blobsLinearHashes[i] == bytes32(0) && output.blobsOpeningCommitments[i] == bytes32(0)) ||
                    (output.blobsLinearHashes[i] != bytes32(0) && output.blobsOpeningCommitments[i] != bytes32(0)),
                "bh"
            );
        }
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IL1DAValidator).interfaceId;
    }
}
