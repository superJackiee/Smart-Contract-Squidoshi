// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

abstract contract LockableFunction {
    bool internal locked;

    modifier lockFunction {
        locked = true;
        _;
        locked = false;
    }
}
