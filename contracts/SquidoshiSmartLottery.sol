// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/utils/Address.sol";
import "@pancakeswap/pancake-swap-lib/contracts/GSN/Context.sol";
import "@pancakeswap/pancake-swap-lib/contracts/utils/EnumerableSet.sol";
import "./interfaces/ISmartLottery.sol";
import "./utils/AuthorizedListExt.sol";
import "./utils/LockableFunction.sol";
import "./utils/LPSwapSupport.sol";
import "./utils/UserInfoManager.sol";

contract SquidoshiSmartLottery is
    ISmartLottery,
    LPSwapSupport,
    LockableFunction,
    AuthorizedListExt,
    UserInfoManager
{
    using EnumerableSet for EnumerableSet.AddressSet;

    RewardType private rewardType;
    IBEP20 public lotteryToken;
    IBEP20 public squidoshiToken;
    uint256 private squidoshiDecimals = 9;
    JackpotRequirements public eligibilityCriteria;
    RewardInfo private rewardTokenInfo;

    address[] public pastWinners;
    EnumerableSet.AddressSet private jackpotParticipants;
    uint256 private maxAttemptsToFindWinner = 10;

    uint256 private jackpot;
    uint256 public override draw = 1;

    uint256 private defaultDecimals = 10**18;

    mapping(uint256 => WinnerLog) public winnersByRound;
    mapping(address => bool) public isExcludedFromJackpot;

    constructor(
        address squidoshi,
        address _router,
        address _rewardsToken
    ) public AuthorizedListExt(true) {
        updateRouter(_router);
        squidoshiToken = IBEP20(payable(squidoshi));
        minSpendAmount = 0;
        maxSpendAmount = 100 ether;

        if (_rewardsToken == address(0)) {
            rewardType = RewardType.CURRENCY;
            rewardTokenInfo.name = "BNB";
            rewardTokenInfo.rewardAddress = address(0);
            rewardTokenInfo.decimals = defaultDecimals;
        } else {
            rewardType = RewardType.TOKEN;
            lotteryToken = IBEP20(payable(_rewardsToken));
            rewardTokenInfo.name = lotteryToken.name();
            rewardTokenInfo.rewardAddress = _rewardsToken;
            rewardTokenInfo.decimals = 10**uint256(lotteryToken.decimals());
        }

        // 100 million
        jackpot = 100 * 10**6 * rewardTokenInfo.decimals;

        eligibilityCriteria = JackpotRequirements({
            minSquidoshiBalance: 10 * 10**6 * 10**9,
            minDrawsSinceLastWin: 1,
            timeSinceLastTransfer: 72 hours
        });

        isExcludedFromJackpot[address(this)] = true;
        isExcludedFromJackpot[squidoshi] = true;
        isExcludedFromJackpot[deadAddress] = true;

        _owner = squidoshi;
    }

    receive() external payable {
        if (!inSwap) swap();
    }

    function deposit() external payable virtual override onlyOwner {
        if (!inSwap) swap();
    }

    function rewardCurrency() external view override returns (string memory) {
        return rewardTokenInfo.name;
    }

    function swap() internal lockTheSwap {
        if (rewardType == RewardType.TOKEN) {
            uint256 contractBalance = address(this).balance;
            swapCurrencyForTokensAdv(
                address(lotteryToken),
                contractBalance,
                address(this)
            );
        }
    }

    function setJackpotToCurrency(bool andSwap)
        external
        virtual
        override
        authorized
    {
        require(
            rewardType != RewardType.CURRENCY,
            "Rewards already set to reflect currency"
        );
        if (!inSwap) resetToCurrency(andSwap);
    }

    function resetToCurrency(bool andSwap) private lockTheSwap {
        uint256 contractBalance = lotteryToken.balanceOf(address(this));
        if (contractBalance > rewardTokenInfo.decimals && andSwap) {
            swapTokensForCurrencyAdv(
                address(lotteryToken),
                contractBalance,
                address(this)
            );
        }
        lotteryToken = IBEP20(0);

        rewardTokenInfo.name = "BNB";
        rewardTokenInfo.rewardAddress = address(0);
        rewardTokenInfo.decimals = defaultDecimals;

        rewardType = RewardType.CURRENCY;
    }

    function setJackpotToToken(address _tokenAddress, bool andSwap)
        external
        virtual
        override
        authorized
    {
        require(
            rewardType != RewardType.TOKEN ||
                _tokenAddress != address(lotteryToken),
            "Rewards already set to reflect this token"
        );
        if (!inSwap) resetToToken(_tokenAddress, andSwap);
    }

    function resetToToken(address _tokenAddress, bool andSwap)
        private
        lockTheSwap
    {
        uint256 contractBalance;
        if (rewardType == RewardType.TOKEN && andSwap) {
            contractBalance = lotteryToken.balanceOf(address(this));
            if (contractBalance > rewardTokenInfo.decimals)
                swapTokensForCurrencyAdv(
                    address(lotteryToken),
                    contractBalance,
                    address(this)
                );
        }
        contractBalance = address(this).balance;
        swapCurrencyForTokensAdv(_tokenAddress, contractBalance, address(this));

        lotteryToken = IBEP20(payable(_tokenAddress));

        rewardTokenInfo.name = lotteryToken.name();
        rewardTokenInfo.rewardAddress = _tokenAddress;
        rewardTokenInfo.decimals = 10**uint256(lotteryToken.decimals());

        rewardType = RewardType.TOKEN;
    }

    function lotteryBalance() public view returns (uint256 balance) {
        balance = _lotteryBalance();
        balance = balance.div(rewardTokenInfo.decimals);
    }

    function _lotteryBalance() internal view returns (uint256 balance) {
        if (rewardType == RewardType.CURRENCY) {
            balance = address(this).balance;
        } else {
            balance = lotteryToken.balanceOf(address(this));
        }
    }

    function jackpotAmount() public view override returns (uint256 balance) {
        balance = jackpot;
        if (rewardTokenInfo.decimals > 0) {
            balance = balance.div(rewardTokenInfo.decimals);
        }
    }

    function setJackpot(uint256 newJackpot) external override authorized {
        require(newJackpot > 0, "Jackpot must be set above 0");
        jackpot = newJackpot;
        if (rewardTokenInfo.decimals > 0) {
            jackpot = jackpot.mul(rewardTokenInfo.decimals);
        }
        emit JackpotSet(rewardTokenInfo.name, newJackpot);
    }

    function checkAndPayJackpot() public override returns (bool) {
        if (_lotteryBalance() >= jackpot && !locked) {
            return _selectAndPayWinner();
        }
        return false;
    }

    function isJackpotReady() external view override returns (bool) {
        return _lotteryBalance() >= jackpot;
    }

    function _selectAndPayWinner()
        private
        lockFunction
        returns (bool winnerFound)
    {
        winnerFound = false;
        uint256 possibleWinner = pseudoRand();
        uint256 numParticipants = jackpotParticipants.length();

        uint256 maxAttempts = maxAttemptsToFindWinner >= numParticipants
            ? numParticipants
            : maxAttemptsToFindWinner;

        for (uint256 attempts = 0; attempts < maxAttempts; attempts++) {
            possibleWinner = possibleWinner.add(attempts);
            if (possibleWinner >= numParticipants) {
                possibleWinner = 0;
            }
            if (_isEligibleForJackpot(jackpotParticipants.at(possibleWinner))) {
                reward(jackpotParticipants.at(possibleWinner));
                winnerFound = true;
                break;
            }
        }
    }

    function reward(address winner) private {
        if (rewardType == RewardType.CURRENCY) {
            winner.call{value: jackpot, gas: 30_000}("");
        } else if (rewardType == RewardType.TOKEN) {
            lotteryToken.transfer(winner, jackpot);
        }
        winnersByRound[draw] = WinnerLog({
            rewardName: rewardTokenInfo.name,
            winnerAddress: winner,
            drawNumber: draw,
            prizeWon: jackpot
        });

        hodlerInfo[winner].lastWin = draw;
        pastWinners.push(winner);

        emit JackpotWon(winner, rewardTokenInfo.name, jackpot, draw);
        ++draw;
    }

    function isEligibleForJackpot(address participant)
        external
        view
        returns (bool)
    {
        if (
            !jackpotParticipants.contains(participant) ||
            hodlerInfo[participant].tokenBalance <
            eligibilityCriteria.minSquidoshiBalance
        ) return false;
        return _isEligibleForJackpot(participant);
    }

    function _isEligibleForJackpot(address participant)
        private
        view
        returns (bool)
    {
        uint256 drawRange = eligibilityCriteria.minDrawsSinceLastWin >= draw
            ? draw
            : eligibilityCriteria.minDrawsSinceLastWin;
        if (
            hodlerInfo[participant].lastTransfer <
            block.timestamp.sub(eligibilityCriteria.timeSinceLastTransfer) &&
            (hodlerInfo[participant].lastWin == 0 ||
                hodlerInfo[participant].lastWin < draw.sub(drawRange))
        ) {
            return !isExcludedFromJackpot[participant];
        }
        return false;
    }

    function pseudoRand() private view returns (uint256) {
        uint256 nonce = draw.add(_lotteryBalance());
        uint256 modulo = jackpotParticipants.length();
        uint256 someValue = uint256(
            keccak256(
                abi.encodePacked(
                    nonce,
                    msg.sender,
                    gasleft(),
                    block.timestamp,
                    draw,
                    jackpotParticipants.at(0)
                )
            )
        );
        return someValue.mod(modulo);
    }

    function excludeFromJackpot(address user, bool shouldExclude)
        public
        override
        authorized
    {
        if (
            isExcludedFromJackpot[user] &&
            !shouldExclude &&
            hodlerInfo[user].tokenBalance >=
            eligibilityCriteria.minSquidoshiBalance
        ) jackpotParticipants.add(user);
        if (!isExcludedFromJackpot[user] && shouldExclude)
            jackpotParticipants.remove(user);
        isExcludedFromJackpot[user] = shouldExclude;
    }

    function logTransfer(
        address payable from,
        uint256 fromBalance,
        address payable to,
        uint256 toBalance
    ) public virtual override(ISmartLottery, UserInfoManager) onlyOwner {
        _logTransfer(from, fromBalance, to, toBalance);
    }

    function _logTransfer(
        address payable from,
        uint256 fromBalance,
        address payable to,
        uint256 toBalance
    ) internal virtual override {
        super._logTransfer(from, fromBalance, to, toBalance);

        if (!isExcludedFromJackpot[from]) {
            if (fromBalance >= eligibilityCriteria.minSquidoshiBalance) {
                jackpotParticipants.add(from);
            } else {
                jackpotParticipants.remove(from);
            }
        }

        if (!isExcludedFromJackpot[to]) {
            if (toBalance >= eligibilityCriteria.minSquidoshiBalance) {
                jackpotParticipants.add(to);
            } else {
                jackpotParticipants.remove(to);
            }
        }
    }

    function _approve(
        address,
        address,
        uint256
    ) internal override {
        require(false);
    }

    function setMaxAttempts(uint256 attemptsToFindWinner)
        external
        override
        authorized
    {
        require(
            attemptsToFindWinner > 0 &&
                attemptsToFindWinner != maxAttemptsToFindWinner,
            "Invalid or duplicate value"
        );
        maxAttemptsToFindWinner = attemptsToFindWinner;
    }

    function setJackpotEligibilityCriteria(
        uint256 minSquidoshiBalance,
        uint256 minDrawsSinceWin,
        uint256 timeSinceLastTransferHours
    ) external override authorized {
        JackpotRequirements memory newCriteria = JackpotRequirements({
            minSquidoshiBalance: minSquidoshiBalance * 10**squidoshiDecimals,
            minDrawsSinceLastWin: minDrawsSinceWin,
            timeSinceLastTransfer: timeSinceLastTransferHours * 1 hours
        });
        emit JackpotCriteriaUpdated(
            minSquidoshiBalance,
            minDrawsSinceWin,
            timeSinceLastTransferHours
        );
        eligibilityCriteria = newCriteria;
    }
}
