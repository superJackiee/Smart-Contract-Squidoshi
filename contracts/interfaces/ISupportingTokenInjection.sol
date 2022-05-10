// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface ISupportingTokenInjection {
    function depositTokens(uint256 liquidityDeposit, uint256 rewardsDeposit, uint256 jackpotDeposit, uint256 buybackDeposit) external;
    function burn(uint256 amount) external;
}
