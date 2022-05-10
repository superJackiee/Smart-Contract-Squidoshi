// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './utils/Ownable.sol';

// On launch, you;ll get X tokens.

interface ISquidoshiReflector {
    function claimDividend() external;
}

interface ISquidoshi is IERC20 {
    function reflectorContract() external returns (ISquidoshiReflector);
}

contract TokenLocker is Ownable {
    address public immutable TOKEN;
    uint256 public immutable UNLOCKTIME;

    constructor(
        address _token,
        address _tokenOwner,
        uint256 _lockDays
    ) public {
        TOKEN = _token;
        _owner = _tokenOwner;
        UNLOCKTIME = block.timestamp + (_lockDays * 1 days);
    }

    function withdrawBNB() public {
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawLockedToken() external {
        require(block.timestamp >= UNLOCKTIME, 'Not unlocked yet!');
        uint256 tokenBalance = ISquidoshi(TOKEN).balanceOf(address(this));
        ISquidoshi(TOKEN).transfer(owner(), tokenBalance);
    }

    function withdrawOtherToken(address _token) external {
        require(_token != TOKEN, 'Cannot withdraw locked token!');
        uint256 tokenBalance = ISquidoshi(_token).balanceOf(address(this));
        ISquidoshi(_token).transfer(owner(), tokenBalance);
    }

    function claimDividend() external {
        ISquidoshi(TOKEN).reflectorContract().claimDividend();
        withdrawBNB();
    }
}
