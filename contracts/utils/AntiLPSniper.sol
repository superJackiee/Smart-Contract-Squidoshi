// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./AuthorizedList.sol";

contract AntiLPSniper is AuthorizedList {
    bool public antiSniperEnabled = true;
    mapping(address => bool) public isBlackListed;

    function banHammer(address user) internal {
        isBlackListed[user] = true;
    }

    function updateBlacklist(address user, bool shouldBlacklist) external onlyOwner {
        isBlackListed[user] = shouldBlacklist;
    }

    function enableAntiSniper(bool enabled) external authorized {
        antiSniperEnabled = enabled;
    }
}
