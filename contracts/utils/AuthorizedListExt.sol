// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../interfaces/IAuthorizedList.sol";
import "./AuthorizedList.sol";

contract AuthorizedListExt is IAuthorizedListExt, AuthorizedList {
    bool private multiAuth;

    constructor(bool allowNonOwnerAuths) public AuthorizedList() {
        multiAuth = allowNonOwnerAuths;
    }

    function authorizeByAuthorized(address authAddress) external virtual override authorized {
        require(multiAuth, "Option not set to allow this function");
        authorizedCaller[authAddress] = true;
        emit AuthorizationUpdated(authAddress, true);
    }
}

