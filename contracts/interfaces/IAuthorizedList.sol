// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IAuthorizedList {
    function authorizeCaller(address authAddress, bool shouldAuthorize) external;
}

interface IAuthorizedListExt {
    function authorizeByAuthorized(address authAddress) external;
}
