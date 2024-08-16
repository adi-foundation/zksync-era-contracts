// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { Call } from "./Common.sol";
import { IRestriction } from "./IRestriction.sol";
import { IChainAdmin } from "./IChainAdmin.sol";
import { IBridgehub } from "../bridgehub/IBridgehub.sol";
import { IZkSyncHyperchain } from "../state-transition/chain-interfaces/IZkSyncHyperchain.sol";
import { IAdmin } from "../state-transition/chain-interfaces/IAdmin.sol";

import { IPermanentRestriction } from "./IPermanentRestriction.sol";

/// @title PermanentRestriction contract
/// @notice This contract should be used by chains that wish to guarantee that certain security 
/// properties are preserved forever.
/// @dev To be deployed as a transparent upgradable proxy, owned by a trusted decentralized governance. 
/// @dev Once of the instances of such contract is to ensure that a ZkSyncHyperchain is a rollup forever.
contract PermanentRestriction is IRestriction, IPermanentRestriction, Ownable2Step {
    /// @notice The address of the Bridgehub contract.
    IBridgehub immutable public BRIDGE_HUB;

    /// @notice The mapping of the allowed admin implementations.
    mapping(bytes32 implementationCodeHash => bool isAllowed) public allowedAdminImplementations;

    /// @notice The mapping of the allowed calls.
    mapping(bytes4 selector => mapping(bytes allowedCalldata => bool isAllowed)) public allowedCalls;

    /// @notice The mapping of the validated selectors.
    mapping(bytes4 selector => bool isValidated) validatedSelectors;

    constructor(address _initialOwner, IBridgehub _bridgehub) {
        BRIDGE_HUB = _bridgehub;

        // solhint-disable-next-line gas-custom-errors, reason-string
        require(_initialOwner != address(0), "Initial owner should be non zero address");
        _transferOwnership(_initialOwner);
    }

    /// @notice Allows a certain `ChainAdmin` implementation to be used as an admin.
    /// @param _implementationHash The hash of the implementation code.
    /// @param _isAllowed The flag that indicates if the implementation is allowed.
    function allowAdminImplementation(bytes32 _implementationHash, bool _isAllowed) external onlyOwner {
        allowedAdminImplementations[_implementationHash] = _isAllowed;

        emit AdminImplementationAllowed(_implementationHash, _isAllowed);
    }

    /// @notice Allows a certain calldata for a selector to be used.
    /// @param _selector The selector of the function.
    /// @param _data The calldata for the function.
    /// @param isAllowed The flag that indicates if the calldata is allowed.
    function setAllowedData(bytes4 _selector, bytes calldata _data, bool isAllowed) external onlyOwner {
        allowedCalls[_selector][_data] = isAllowed;

        emit AllowedDataChanged(_selector, _data, isAllowed);
    }
    
    /// @notice Allows a certain selector to be validated.
    /// @param _selector The selector of the function.
    /// @param _isValidated The flag that indicates if the selector is validated.
    function setSelectorIsValidated(bytes4 _selector, bool _isValidated) external onlyOwner {
        validatedSelectors[_selector] = _isValidated;

        emit SelectorValidationChanged(_selector, _isValidated);
    }

    /// @inheritdoc IRestriction
    function validateCall(
        Call calldata _call,
        address // _invoker
    ) external view override {
        _validateAsChainAdmin(_call);
        _validateRemoveRestriction(_call);
    }

    /// @notice Validates the call as the chain admin
    /// @param _call The call data.
    function _validateAsChainAdmin(Call calldata _call) internal view {
        if(!_isAdminOfAChain(_call.target)) {
            // We only validate calls related to being an admin of a chain
            return;
        }

        // All calls with the length of the data below 4 will get into `receive`/`fallback` functions,
        // we consider it to always be allowed.
        if (_call.data.length < 4) {
            return;
        }

        bytes4 selector = bytes4(_call.data[:4]);

        if (selector == IAdmin.setPendingAdmin.selector) {
            _validateNewAdmin(_call);
            return;
        }

        if (!validatedSelectors[selector]) {
            // The selector is not validated, any data is allowed.
            return;
        }
        
        require(allowedCalls[selector][_call.data], "not allowed");
    }

    /// @notice Validates the correctness of the new admin.
    /// @param _call The call data.
    /// @dev Ensures that the admin has a whitelisted implementation and does not remove this restriction.
    function _validateNewAdmin(Call calldata _call) internal view {
        address newChainAdmin = abi.decode(_call.data[4:], (address));
        
        bytes32 implementationCodeHash;
        assembly {
            implementationCodeHash := extcodehash(newChainAdmin)
        }
        require(allowedAdminImplementations[implementationCodeHash], "Unallowed implementation");

        // Since the implementation is known to be corect (from the checks above), we 
        // can safely trust the returned value from the call below
        require(IChainAdmin(newChainAdmin).isRestrictionActive(address(this)), "This restriction is permanent");
    }

    /// @notice Validates the removal of the restriction.
    /// @param _call The call data.
    /// @dev Ensures that this restriction is not removed.
    function _validateRemoveRestriction(Call calldata _call) internal view {
        if(_call.target != msg.sender) {
            return;
        }

        if (bytes4(_call.data[:4]) != IChainAdmin.removeRestriction.selector) {
            return;
        }

        address removedRestriction = abi.decode(_call.data[4:], (address));

        require(removedRestriction != address(this), "This restriction is permanent");
    }

    /// @notice Checks if the `msg.sender` is an admin of a certain ZkSyncHyperchain.
    /// @param _chain The address of the chain.
    function _isAdminOfAChain(address _chain) internal view returns (bool) {
        (bool success, ) = address(this).staticcall(abi.encodeCall(this.tryCompareAdminOfAChain, (_chain, msg.sender)));
        return success;
    }

    /// @notice Tries to compare the admin of a chain with the potential admin.
    /// @param _chain The address of the chain.
    /// @param _potentialAdmin The address of the potential admin.
    /// @dev This function reverts if the `_chain` is not a ZkSyncHyperchain or the `_potentialAdmin` is not the 
    /// admin of the chain.
    function tryCompareAdminOfAChain(address _chain, address _potentialAdmin) external view {
        require(_chain != address(0), "Address 0 is never a chain");

        // Unfortunately there is no easy way to double check that indeed the `_chain` is a ZkSyncHyperchain.
        // So we do the following:
        // - Query it for `chainId`. If it reverts, it is not a ZkSyncHyperchain.
        // - Query the Bridgehub for the Hyperchain with the given `chainId`. 
        // - We compare the corresponding addresses
        uint256 chainId = IZkSyncHyperchain(_chain).getChainId();
        require(BRIDGE_HUB.getHyperchain(chainId) == _chain, "Not a Hyperchain");

        // Now, the chain is known to be a hyperchain, so it should implement the corresponding interface        
        address admin = IZkSyncHyperchain(_chain).getAdmin();
        require(admin == _potentialAdmin, "Not an admin");
    }
}
