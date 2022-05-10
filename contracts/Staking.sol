// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';

contract Staking is Ownable {
    using SafeMath for uint256;

    struct Deposit {
        uint256 tokenAmount;
        uint256 weight;
        uint256 lockedUntil;
        uint256 rewardDebt;
        uint256 rewardDebtAlt;
    }

    struct UserInfo {
        uint256 tokenAmount;
        uint256 totalWeight;
        uint256 totalRewardsClaimed;
        uint256 totalRewardsClaimedAlt;
        Deposit[] deposits;
    }

    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant MULTIPLIER = 1e12;

    uint256 public constant TOTAL_LOCK_MODES = 4;
    uint256 public constant LOCK_DUR_MIN = 7 * ONE_DAY;
    uint256 public constant LOCK_DUR_MID = 14 * ONE_DAY;
    uint256 public constant LOCK_DUR_MAX = 31 * ONE_DAY;

    uint256 public accTokenPerUnitWeight; // Accumulated TKNs per weight, times MULTIPLIER.
    uint256 public accTokenPerUnitWeightAlt; // Accumulated TKNAlt per weight, times MULTIPLIER.

    // total locked amount across all users
    uint256 public usersLockingAmount;
    // total locked weight across all users
    uint256 public usersLockingWeight;

    // The staking and reward token
    IERC20 public immutable token;
    // The alt reward token
    IERC20 public immutable tokenAlt;

    // the reward rates
    uint256 public rateMin;
    uint256 public rateMid;
    uint256 public rateMax;

    // The accounting of unclaimed TKN rewards
    uint256 public unclaimedTokenRewards;
    uint256 public unclaimedTokenRewardsAlt;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 rewardAmount, uint256 rewardAmountAlt);
    event RatesUpdated(uint256 rateMin, uint256 rateMid, uint256 rateMax);

    constructor(
        IERC20 _token,
        IERC20 _tokenAlt,
        uint256 _rateMin,
        uint256 _rateMid,
        uint256 _rateMax
    ) public {
        token = _token;
        tokenAlt = _tokenAlt;

        rateMin = _rateMin;
        rateMid = _rateMid;
        rateMax = _rateMax;
    }

    // Returns total staked token balance for the given address
    function balanceOf(address _user) external view returns (uint256) {
        return userInfo[_user].tokenAmount;
    }

    // Returns total staked token weight for the given address
    function weightOf(address _user) external view returns (uint256) {
        return userInfo[_user].totalWeight;
    }

    // Returns total claimed tokens of type 1 for the given address
    function totalClaimed(address _user) external view returns (uint256) {
        return userInfo[_user].totalRewardsClaimed;
    }

    // Returns total claimed tokens of type Alt for the given address
    function totalClaimedAlt(address _user) external view returns (uint256) {
        return userInfo[_user].totalRewardsClaimedAlt;
    }

    // Returns information on the given deposit for the given address
    function getDeposit(address _user, uint256 _depositId) external view returns (uint256, uint256, uint256, uint256, uint256) {
        Deposit storage stakeDeposit = userInfo[_user].deposits[_depositId];
        return (stakeDeposit.tokenAmount, stakeDeposit.weight, stakeDeposit.lockedUntil, stakeDeposit.rewardDebt, stakeDeposit.rewardDebtAlt);
    }

    // Returns number of deposits for the given address. Allows iteration over deposits.
    function getDepositsLength(address _user) external view returns (uint256) {
        return userInfo[_user].deposits.length;
    }

    function getPendingRewardOf(address _staker, uint256 _depositId) external view returns(uint256, uint256) {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 _amount = stakeDeposit.tokenAmount;
        uint256 _weight = stakeDeposit.weight;
        uint256 _rewardDebt = stakeDeposit.rewardDebt;
        uint256 _rewardDebtAlt = stakeDeposit.rewardDebtAlt;

        // calculate reward upto current block
        uint256 tokenReward = token.balanceOf(address(this)) - usersLockingAmount - unclaimedTokenRewards;
        uint256 _accTokenPerUnitWeight = accTokenPerUnitWeight + (tokenReward * MULTIPLIER) / usersLockingWeight;
        uint256 _rewardAmount = ((_weight * _accTokenPerUnitWeight) / MULTIPLIER) - _rewardDebt;

        uint256 tokenRewardAlt = tokenAlt.balanceOf(address(this)) - unclaimedTokenRewardsAlt;
        uint256 _accTokenPerUnitWeightAlt = accTokenPerUnitWeightAlt + (tokenRewardAlt * MULTIPLIER) / usersLockingWeight;
        uint256 _rewardAmountAlt = ((_weight * _accTokenPerUnitWeightAlt) / MULTIPLIER) - _rewardDebtAlt;

        return (_rewardAmount, _rewardAmountAlt);
    }

    function getUnlockSpecs(uint256 _amount, uint256 _lockMode) public view returns(uint256 lockUntil, uint256 weight) {
        require(_lockMode < TOTAL_LOCK_MODES, "Staking: Invalid lock mode");

        if(_lockMode == 0) {
            // 0 : no lock
            return (now256(), _amount);
        }
        else if(_lockMode == 1) {
            // 1 : 7-day lock
            return (now256() + LOCK_DUR_MIN * ONE_DAY, (_amount * (100 + rateMin)) / 100);
        }
        else if(_lockMode == 2) {
            // 2 : 14-day lock
            return (now256() + LOCK_DUR_MID * ONE_DAY, (_amount * (100 + rateMid)) / 100);
        }

        // 3 : 31-day lock
        return (now256() + LOCK_DUR_MAX * ONE_DAY, (_amount * (100 + rateMax)) / 100);
    }

    function now256() public view returns (uint256) {
        // return current block timestamp
        return block.timestamp;
    }

    function updateRates(uint256 _rateMin, uint256 _rateMid, uint256 _rateMax) external onlyOwner {
        require(_rateMin < 100, "Staking: Invalid rate");
        require(_rateMid < 100, "Staking: Invalid rate");
        require(_rateMax < 100, "Staking: Invalid rate");
        rateMin = _rateMin;
        rateMid = _rateMid;
        rateMax = _rateMax;

        emit RatesUpdated(_rateMin, _rateMid, _rateMax);
    }

    // Added to support recovering lost tokens that find their way to this contract
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(token), "TKNStaking: Cannot withdraw the staking token");
        require(_tokenAddress != address(tokenAlt), "TKNStaking: Cannot withdraw the rewards token");
        IERC20(_tokenAddress).transfer(msg.sender, _tokenAmount);
    }

    // Update reward variables
    function sync() external {
        _sync();
    }

    // Stake tokens
    function stake(uint256 _amount, uint256 _lockMode) external {
        _stake(msg.sender, _amount, _lockMode);
    }

    // Unstake tokens and claim rewards
    function unstake(uint256 _depositId) external {
        _unstake(msg.sender, _depositId, true);
    }

    // Claim rewards
    function claimRewards(uint256 _depositId) external {
        _claimRewards(msg.sender, _depositId);
    }

    function claimRewardsBatch(uint256[] calldata _depositIds) external {
        for(uint256 i = 0; i < _depositIds.length; i++) {
            _claimRewards(msg.sender, _depositIds[i]);
        }
    }

    // TODO
    function autoBuyUsingRewards(uint256[] calldata _depositIds) external {
        // buys SQDI with all BUSD rewards earned by the user, and stakes them
    }

    // Unstake tokens withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _depositId) external {
        _unstake(msg.sender, _depositId, false);
    }

    function _sync() internal {
        uint256 _weightLocked = usersLockingWeight;
        if (_weightLocked == 0) {
            return;
        }

        uint256 tokenReward = token.balanceOf(address(this)) - usersLockingAmount - unclaimedTokenRewards;
        unclaimedTokenRewards += tokenReward;
        accTokenPerUnitWeight += (tokenReward * MULTIPLIER) / _weightLocked;

        uint256 tokenRewardAlt = tokenAlt.balanceOf(address(this)) - unclaimedTokenRewardsAlt;
        unclaimedTokenRewardsAlt += tokenRewardAlt;
        accTokenPerUnitWeightAlt += (tokenRewardAlt * MULTIPLIER) / _weightLocked;
    }

    function _stake(address _staker, uint256 _userAmount, uint256 _lockMode) internal {
        _sync();

        UserInfo storage user = userInfo[_staker];

        uint256 _amount = _transferTokenFrom(address(_staker), address(this), _userAmount);
        require(_amount > 0, "TKNStaking: Deposit amount is 0");

        (uint256 lockUntil, uint256 stakeWeight) = getUnlockSpecs(_amount, _lockMode);

        // create and save the deposit (append it to deposits array)
        Deposit memory deposit =
            Deposit({
                tokenAmount: _amount,
                weight: stakeWeight,
                lockedUntil: lockUntil,
                rewardDebt: (stakeWeight*accTokenPerUnitWeight) / MULTIPLIER,
                rewardDebtAlt: (stakeWeight*accTokenPerUnitWeightAlt) / MULTIPLIER
            });
        // deposit ID is an index of the deposit in `deposits` array
        user.deposits.push(deposit);

        user.tokenAmount += _amount;
        user.totalWeight += stakeWeight;

        // update global variable
        usersLockingWeight += stakeWeight;
        usersLockingAmount += _amount;

        emit Staked(_staker, _amount);
    }

    function _unstake(address _staker, uint256 _depositId, bool _sendRewards) internal {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 _amount = stakeDeposit.tokenAmount;
        uint256 _weight = stakeDeposit.weight;
        uint256 _rewardDebt = stakeDeposit.rewardDebt;
        uint256 _rewardDebtAlt = stakeDeposit.rewardDebtAlt;

        require(_amount > 0, "TKNStaking: Deposit amount is 0");
        require(now256() > stakeDeposit.lockedUntil, "TKNStaking: Deposit not unlocked yet");

        if(_sendRewards) {
            _sync();
        }

        uint256 _rewardAmount = ((_weight * accTokenPerUnitWeight) / MULTIPLIER) - _rewardDebt;
        uint256 _rewardAmountAlt = ((_weight * accTokenPerUnitWeightAlt) / MULTIPLIER) - _rewardDebtAlt;

        // update user record
        user.tokenAmount -= _amount;
        user.totalWeight = user.totalWeight - _weight;
        user.totalRewardsClaimed += _rewardAmount;
        user.totalRewardsClaimedAlt += _rewardAmountAlt;

        // update global variable
        usersLockingWeight -= _weight;
        usersLockingAmount -= _amount;
        unclaimedTokenRewards -= _rewardAmount;
        unclaimedTokenRewardsAlt -= _rewardAmountAlt;

        uint256 tokenToSend = _amount;
        if(_sendRewards) {
            // add rewards
            tokenToSend += _rewardAmount;
            _safeTokenTransferAlt(_staker, _rewardAmountAlt);
            emit Claimed(_staker, _rewardAmount, _rewardAmountAlt);
        }

        delete user.deposits[_depositId];

        // return tokens back to holder
        _safeTokenTransfer(_staker, tokenToSend);
        emit Unstaked(_staker, _amount);
    }

    function _claimRewards(address _staker, uint256 _depositId) internal {
        UserInfo storage user = userInfo[_staker];
        Deposit storage stakeDeposit = user.deposits[_depositId];

        uint256 _amount = stakeDeposit.tokenAmount;
        uint256 _weight = stakeDeposit.weight;
        uint256 _rewardDebt = stakeDeposit.rewardDebt;
        uint256 _rewardDebtAlt = stakeDeposit.rewardDebtAlt;

        require(_amount > 0, "TKNStaking: Deposit amount is 0");
        _sync();

        uint256 _rewardAmount = ((_weight * accTokenPerUnitWeight) / MULTIPLIER) - _rewardDebt;
        uint256 _rewardAmountAlt = ((_weight * accTokenPerUnitWeightAlt) / MULTIPLIER) - _rewardDebtAlt;

        // update stakeDeposit record
        stakeDeposit.rewardDebt += _rewardAmount;
        stakeDeposit.rewardDebtAlt += _rewardAmountAlt;

        // update user record
        user.totalRewardsClaimed += _rewardAmount;
        user.totalRewardsClaimedAlt += _rewardAmountAlt;

        // update global variable
        unclaimedTokenRewards -= _rewardAmount;
        unclaimedTokenRewardsAlt -= _rewardAmountAlt;

        // return tokens back to holder
        _safeTokenTransfer(_staker, _rewardAmount);
        _safeTokenTransferAlt(_staker, _rewardAmountAlt);
        emit Claimed(_staker, _rewardAmount, _rewardAmountAlt);
    }

    function _transferTokenFrom(address _from, address _to, uint256 _value) internal returns (uint256) {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.transferFrom(_from, _to, _value);
        return token.balanceOf(address(this)) - balanceBefore;
    }

    // Safe token transfer function, just in case if rounding error causes contract to not have enough TKN.
    function _safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            IERC20(token).transfer(_to, tokenBal);
        } else {
            IERC20(token).transfer(_to, _amount);
        }
    }

    // Safe token transfer function, just in case if rounding error causes contract to not have enough TKN.
    function _safeTokenTransferAlt(address _to, uint256 _amount) internal {
        uint256 tokenBal = tokenAlt.balanceOf(address(this));
        if (_amount > tokenBal) {
            IERC20(tokenAlt).transfer(_to, tokenBal);
        } else {
            IERC20(tokenAlt).transfer(_to, _amount);
        }
    }
}
