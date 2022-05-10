// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./IBaseDistributor.sol";
import "./IUserInfoManager.sol";
import "./IAuthorizedList.sol";

interface ISmartLottery is IBaseDistributor, IAuthorizedListExt, IAuthorizedList {
    struct WinnerLog{
        string rewardName;
        address winnerAddress;
        uint256 drawNumber;
        uint256 prizeWon;
    }

    struct JackpotRequirements{
        uint256 minSquidoshiBalance;
        uint256 minDrawsSinceLastWin;
        uint256 timeSinceLastTransfer;
    }

    event JackpotSet(string indexed tokenName, uint256 JackpotAmount);
    event JackpotWon(address indexed winner, string indexed reward, uint256 amount, uint256 drawNo);
    event JackpotCriteriaUpdated(uint256 minSquidoshiBalance, uint256 minDrawsSinceLastWin, uint256 timeSinceLastTransfer);

    function draw() external pure returns(uint256);
    function jackpotAmount() external view returns(uint256);
    function isJackpotReady() external view returns(bool);
    function setJackpot(uint256 newJackpot) external;
    function checkAndPayJackpot() external returns(bool);
    function excludeFromJackpot(address shareholder, bool shouldExclude) external;
    function setMaxAttempts(uint256 attemptsToFindWinner) external;

    function setJackpotToCurrency(bool andSwap) external;
    function setJackpotToToken(address _tokenAddress, bool andSwap) external;
    function setJackpotEligibilityCriteria(uint256 minSquidoshiBalance, uint256 minDrawsSinceWin, uint256 timeSinceLastTransferHours) external;
    function logTransfer(address payable from, uint256 fromBalance, address payable to, uint256 toBalance) external;
}