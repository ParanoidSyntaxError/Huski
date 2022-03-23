// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./HuskiToken.sol";

contract HuskiStake is HuskiToken
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

    uint256 private _earningPool;

    uint256 private _totalShares;
    uint256 private _totalStaked;

    mapping(address => Stake[]) private _stakes;
    
    mapping(uint256 => StakingOption) private _stakingOptions;

    constructor()
    {
        _stakingOptions[0] = StakingOption(30 days, 0);     //1 month
        _stakingOptions[1] = StakingOption(90 days, 10);    //3 months
        _stakingOptions[2] = StakingOption(180 days, 25);   //6 months
        _stakingOptions[3] = StakingOption(360 days, 60);   //1 year
        _stakingOptions[4] = StakingOption(720 days, 140);  //2 years
    }

    function stakePool() public view returns (uint256)
    {
        return _totalStaked + _earningPool;
    }

    function deposit(uint256 amount, uint256 optionIndex) external 
    {      
        require(amount > 0);

        address sender = _msgSender();

        require(_balances[sender] <= amount);

        uint256 stakeBonus = _stakingOptions[optionIndex].bonus;
        uint256 unlockTime = _stakingOptions[optionIndex].duration + block.timestamp;
    
        uint256 newShares = (amount * (100 + stakeBonus)) / 100;

        _totalStaked += amount;
        _totalShares += newShares;
        
        _balances[sender] -= amount;
        _balances[address(this)] += amount;
        
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
    }

    function withdraw(uint256 index) external 
    {
        address sender = _msgSender();

        uint256 stakeCount = _stakes[msg.sender].length;
        require(index < stakeCount);

        Stake memory stake = _stakes[sender][index];

        require(stake.amount > 0);
        require(stake.unlockTime <= block.timestamp);
               
        uint256 shares = (stake.amount * (100 + stake.bonus)) / 100;

        uint256 earnings = shares * (_earningPool / _totalShares);

        _earningPool -= earnings;

        _totalStaked -= stake.amount;
        _totalShares -= shares;

        uint256 withdrawAmount = stake.amount + earnings;

        _balances[sender] += withdrawAmount;
        _balances[address(this)] -= withdrawAmount;

        _stakes[sender][index].amount = 0;
    }

    function _stakeFee(uint256 amount) internal override 
    {
        _earningPool += amount;
    }
}