// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

// solhint-disable gas-custom-errors, reason-string

import {IL2DAValidator} from "../interfaces/IL2DAValidator.sol";
import {StateDiffL2DAValidator} from "./StateDiffL2DAValidator.sol";
import {PUBDATA_CHUNK_PUBLISHER} from "../L2ContractHelper.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// Rollup DA validator. It will publish data that would allow to use either calldata or blobs.
contract ValidiumL2DAValidator is IL2DAValidator, StateDiffL2DAValidator {
    function validatePubdata(
        // The rolling hash of the user L2->L1 logs.
        bytes32 chainedLogsHash,
        // The root hash of the user L2->L1 logs.
        bytes32 logsRootHash,
        // The chained hash of the L2->L1 messages
        bytes32 chainedMessagesHash,
        // The chained hash of uncompressed bytecodes sent to L1
        bytes32 chainedBytescodesHash,
        // Operator data, that is related to the DA itself
        bytes calldata _totalL2ToL1PubdataAndStateDiffs
    ) external returns (bytes32 outputHash) {
        // Since we do not need to publish anything to L1, we can just return 0.
        // Note, that Rollup validator sends the hash of uncompressed state diffs, since the
        // correctness of the publish pubdata depends on it. However Validium doesnt sent anythng,
        // so we don't need to publish even that.
        outputHash = bytes32(0);
    }
}