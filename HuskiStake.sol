// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Huski.sol";

contract HuskiStake
{
   struct Stake 
   {
        uint256 amount;
        uint256 startTime;
        uint256 startEarnings;
        uint256 option;
    }
    
    struct StakingOption 
    {
        uint256 duration;
        uint256 bonus;
    }

    uint256 public totalShares;
    uint256 public totalStaked;
    
    uint256 public cumulativeEarnings;
    uint256 public remainingEarnings;

    mapping(address => Stake[5]) public stakes;
    
    StakingOption[6] public stakingOptions;

    Huski private _hski;

    constructor(Huski huskiContract)
    {
        _hski = huskiContract;

        stakingOptions[0] = StakingOption(30 days, 0);     //1 month
        stakingOptions[1] = StakingOption(90 days, 10);    //3 months
        stakingOptions[2] = StakingOption(180 days, 25);   //6 months
        stakingOptions[3] = StakingOption(360 days, 60);   //1 year
        stakingOptions[4] = StakingOption(720 days, 140);  //2 years
        stakingOptions[5] = StakingOption(1800 days, 390); //5 years

        stakingOptions[0] = StakingOption(0, 0);
    }

    function stakeEarnings(address account, uint256 stakeIndex) public view returns (uint256)
    {
        uint256 sharesPerWei = (totalShares * 1000) / (cumulativeEarnings - stakes[account][stakeIndex].startEarnings);

        if(block.timestamp > stakes[account][stakeIndex].startTime + stakingOptions[stakes[account][stakeIndex].option].duration + 30 days)
        {
            uint256 penalty = ((block.timestamp - stakingOptions[stakes[account][stakeIndex].option].duration) * 1000) / stakingOptions[stakes[account][stakeIndex].option].duration;

            sharesPerWei = (sharesPerWei * penalty) - sharesPerWei;
        }

        return (_shareAmount(stakes[account][stakeIndex].amount, stakes[account][stakeIndex].option) * 1000) / sharesPerWei;
    }

    function depositStake(uint256 amount, uint256 optionIndex) external
    {
        require(amount > 0);
        require(optionIndex < stakingOptions.length);
        require(_hski.balanceOf(msg.sender) >= amount);

        _hski.burn(amount);

        bool stakesFull = true;

        for(uint256 i = 0; i < stakes[msg.sender].length; i++)
        {
            if(stakes[msg.sender][i].amount == 0)
            {
                stakes[msg.sender][i] = Stake(amount, block.timestamp, cumulativeEarnings, optionIndex);

                uint256 newShares = _shareAmount(amount, optionIndex);

                totalShares += newShares;
                totalStaked += amount;

                stakesFull = false;
                break;
            }
        }

        require(stakesFull == false);
    }

    function withdrawStake(uint256 index) external
    {
        require(index < stakes[msg.sender].length);

        Stake memory stake = stakes[msg.sender][index];

        require(stake.amount > 0);
        require(block.timestamp >= stake.startTime + stakingOptions[stake.option].duration);
               
        uint256 shares = _shareAmount(stake.amount, stake.option);

        uint256 earnings = stakeEarnings(msg.sender, index);

        totalStaked -= stake.amount;
        totalShares -= shares;

        remainingEarnings -= earnings;

        stakes[msg.sender][index].amount = 0;

        _hski.taxFreeTransfer(_hski.huskiPool(), msg.sender, stake.amount + earnings);
    }

    function _stakeFee(uint256 amount) internal
    {
        cumulativeEarnings += amount;
        remainingEarnings += amount;
    }

    function _shareAmount(uint256 amount, uint256 optionIndex) private view returns (uint256)
    {
        return (amount * (100 + stakingOptions[optionIndex].bonus)) / 100;
    }
}