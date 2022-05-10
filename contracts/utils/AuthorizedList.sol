// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IAuthorizedList.sol';

contract AuthorizedList is IAuthorizedList, Context, Ownable {
    using Address for address;

    event AuthorizationUpdated(address indexed user, bool authorized);
    event AuthorizationRenounced(address indexed user);

    mapping(address => bool) internal authorizedCaller;

    modifier authorized() {
        require(authorizedCaller[_msgSender()] || _msgSender() == owner(), 'not authorized');
        require(_msgSender() != address(0), 'Invalid caller');
        _;
    }

    constructor() public Ownable() {
        authorizedCaller[_msgSender()] = true;
    }

    function authorizeCaller(address authAddress, bool shouldAuthorize) external virtual override onlyOwner {
        authorizedCaller[authAddress] = shouldAuthorize;
        emit AuthorizationUpdated(authAddress, shouldAuthorize);
    }

    function renounceAuthorization() external authorized {
        authorizedCaller[_msgSender()] = false;
        emit AuthorizationRenounced(_msgSender());
    }
}
