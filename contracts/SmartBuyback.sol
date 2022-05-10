// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./utils/AuthorizedList.sol";
import "./utils/LPSwapSupport.sol";

abstract contract SmartBuyback is AuthorizedList, LPSwapSupport {
    event BuybackTriggered(uint256 amountSpent);
    event BuybackReceiverUpdated(
        address indexed oldReceiver,
        address indexed newReceiver
    );

    uint256 public minAutoBuyback = 0.05 ether;
    uint256 public maxAutoBuyback = 10 ether;
    uint256 private significantLPBuyPct = 1;
    uint256 private significantLPBuyPctDivisor = 100;
    bool public autoBuybackEnabled;
    bool public autoBuybackAtCap = true;
    bool public doSimpleBuyback;
    address public buybackReceiver = deadAddress;
    uint256 private lastBuybackAmount;
    uint256 private lastBuybackTime;
    uint256 private lastBuyPoolSize;

    function shouldBuyback(uint256 poolTokens, uint256 sellAmount)
        public
        view
        returns (bool)
    {
        return
            (poolTokens.mul(significantLPBuyPct).div(
                significantLPBuyPctDivisor
            ) >=
                sellAmount &&
                autoBuybackEnabled &&
                address(this).balance >= minAutoBuyback) ||
            (autoBuybackAtCap && address(this).balance >= maxAutoBuyback);
    }

    function doBuyback(uint256 poolTokens, uint256 sellAmount) internal {
        if (
            autoBuybackEnabled &&
            !inSwap &&
            address(this).balance >= minAutoBuyback
        ) _doBuyback(poolTokens, sellAmount);
    }

    function _doBuyback(uint256 poolTokens, uint256 sellAmount)
        private
        lockTheSwap
    {
        uint256 lpMin = minSpendAmount;
        uint256 lpMax = maxSpendAmount;
        minSpendAmount = minAutoBuyback;
        maxSpendAmount = maxAutoBuyback;
        if (autoBuybackAtCap && address(this).balance >= maxAutoBuyback) {
            simpleBuyback(poolTokens, 0);
        } else if (doSimpleBuyback) {
            simpleBuyback(poolTokens, sellAmount);
        } else {
            dynamicBuyback(poolTokens, sellAmount);
        }
        minSpendAmount = lpMin;
        maxSpendAmount = lpMax;
    }

    function _doBuybackNoLimits(uint256 amount) private lockTheSwap {
        uint256 lpMin = minSpendAmount;
        uint256 lpMax = maxSpendAmount;
        minSpendAmount = 0;
        maxSpendAmount = amount;
        swapCurrencyForTokensAdv(address(this), amount, buybackReceiver);
        emit BuybackTriggered(amount);
        minSpendAmount = lpMin;
        maxSpendAmount = lpMax;
    }

    function simpleBuyback(uint256 poolTokens, uint256 sellAmount) private {
        uint256 amount = address(this).balance > maxAutoBuyback
            ? maxAutoBuyback
            : address(this).balance;
        if (amount >= minAutoBuyback) {
            if (sellAmount == 0) {
                amount = minAutoBuyback;
            }
            swapCurrencyForTokensAdv(address(this), amount, buybackReceiver);
            emit BuybackTriggered(amount);
            lastBuybackAmount = amount;
            lastBuybackTime = block.timestamp;
            lastBuyPoolSize = poolTokens;
        }
    }

    function dynamicBuyback(uint256 poolTokens, uint256 sellAmount) private {
        if (lastBuybackTime == 0) {
            simpleBuyback(poolTokens, sellAmount);
        }
        uint256 amount = sellAmount.mul(address(pancakePair).balance).div(
            poolTokens
        );
        if (lastBuyPoolSize < poolTokens) {
            amount = amount.add(
                amount.mul(poolTokens).div(poolTokens.add(lastBuyPoolSize))
            );
        }

        swapCurrencyForTokensAdv(address(this), amount, buybackReceiver);
        emit BuybackTriggered(amount);
        lastBuybackAmount = amount;
        lastBuybackTime = block.timestamp;
        lastBuyPoolSize = poolTokens;
    }

    function enableAutoBuybacks(bool enable, bool autoBuybackAtCapEnabled)
        external
        authorized
    {
        autoBuybackEnabled = enable;
        autoBuybackAtCap = autoBuybackAtCapEnabled;
    }

    function updateBuybackSettings(
        uint256 lpSizePct,
        uint256 pctDivisor,
        bool simpleBuybacksOnly
    ) external authorized {
        significantLPBuyPct = lpSizePct;
        significantLPBuyPctDivisor = pctDivisor;
        doSimpleBuyback = simpleBuybacksOnly;
    }

    function updateBuybackLimits(uint256 minBuyAmount, uint256 maxBuyAmount)
        external
        authorized
    {
        minAutoBuyback = minBuyAmount;
        maxAutoBuyback = maxBuyAmount;
    }

    function forceBuyback(uint256 amount) external authorized {
        require(address(this).balance >= amount);
        if (!inSwap) {
            _doBuybackNoLimits(amount);
        }
    }

    function updateBuybackReceiver(address newReceiver) external onlyOwner {
        emit BuybackReceiverUpdated(buybackReceiver, newReceiver);
        buybackReceiver = newReceiver;
    }
}
