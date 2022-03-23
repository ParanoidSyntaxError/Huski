// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./HuskiToken.sol";

contract HuskiStake
{
   struct Stake 
   {
        uint256 amount;
        uint256 unlockTime;
        uint256 bonus;
    }
    
    struct StakingOption 
    {
        uint256 duration;
        uint256 bonus;
    }

    uint256 private _totalShares;
    uint256 private _totalStaked;
    
    uint256 private _stakeEarnings;

    mapping(address => Stake[5]) private _stakes;
    
    StakingOption[5] private _stakingOptions;

    HuskiToken private _hski;

    constructor(HuskiToken token)
    {
        _hski = token;

        _stakingOptions[0] = StakingOption(30 days, 0);     //1 month
        _stakingOptions[1] = StakingOption(90 days, 10);    //3 months
        _stakingOptions[2] = StakingOption(180 days, 25);   //6 months
        _stakingOptions[3] = StakingOption(360 days, 60);   //1 year
        _stakingOptions[4] = StakingOption(720 days, 140);  //2 years
    }

    function stakePool() external view returns(uint256)
    {
        return _hski.stakePool();
    }

    function getStakes(address account) external view returns (uint256[5][4] memory stakes)
    {
        for(uint256 i = 0; i < _stakes[account].length; i++)
        {
            stakes[i][0] = _stakes[account][i].amount;
            stakes[i][1] = _stakes[account][i].bonus;
            stakes[i][2] = _getEarnings(account, i);
            stakes[i][3] = _stakes[account][i].unlockTime;
        }

        return stakes;
    }

    function _getEarnings(address account, uint256 index) private view returns (uint256)
    {
        return ((_stakes[account][index].amount * (100 + _stakes[account][index].bonus)) / 100) * (_stakeEarnings / _totalShares);
    }

    function _getShares(address account, uint256 index) private view returns (uint256)
    {
        return (_stakes[account][index].amount * (100 + _stakes[account][index].bonus)) / 100;
    }

    function depositStake(uint256 amount, uint256 optionIndex) external 
    {      
        require(amount > 0);
        require(optionIndex < _stakingOptions.length);

        address sender = msg.sender;

        require(_hski.balanceOf(sender) >= amount);

        _hski.transfer(sender, address(this), amount);

        uint256 stakeBonus = _stakingOptions[optionIndex].bonus;
        uint256 unlockTime = _stakingOptions[optionIndex].duration + block.timestamp;

        bool stakesFull = true;

        for(uint256 i = 0; i < _stakes[sender].length; i++)
        {
            if(_stakes[sender][i].amount == 0)
            {
                _stakes[sender][i] = Stake(amount, unlockTime, stakeBonus);
                stakesFull = false;
                break;
            }
        }

        if(stakesFull == true)
        {
            revert();
        }
    
        uint256 newShares = (amount * (100 + stakeBonus)) / 100;

        _totalStaked += amount;
        _totalShares += newShares;

        _hski.setStakePool(_hski.stakePool() + amount);
    }

    function withdrawStake(uint256 index) external 
    {
        address sender = msg.sender;

        uint256 stakeCount = _stakes[msg.sender].length;
        require(index < stakeCount);

        Stake memory stake = _stakes[sender][index];

        require(stake.amount > 0);
        require(stake.unlockTime <= block.timestamp);
               
        _stakes[sender][index].amount = 0;

        uint256 shares = _getShares(sender, index);

        uint256 earnings = _getEarnings(sender, index);

        _totalStaked -= stake.amount;
        _stakeEarnings -= earnings;
        _totalShares -= shares;

        _hski.setStakePool(_hski.stakePool() - (stake.amount + earnings));

        uint256 withdrawAmount = stake.amount + earnings;

        _hski.transfer(sender, address(this), withdrawAmount);
    }

    function _stakeFee(uint256 amount) internal 
    {
        _stakeEarnings += amount;
        _hski.setStakePool(_hski.stakePool() + amount);
    }
}