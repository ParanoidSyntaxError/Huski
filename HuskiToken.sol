// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HuskiToken
{
    string public constant NAME = "Huski";
    string public constant SYMBOL = "HSKI";
    uint8 public constant DECIMALS = 18;

    uint256 public constant TOTAL_SUPPLY = (10**9) * (10**DECIMALS); //1 billion

    uint256 public constant STAKE_TAX = 2;
    uint256 public constant BURN_TAX = 1;
    uint256 public constant LOTTERY_TAX = 2;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _taxExclusions;

    uint256 public totalStakeFees;
    uint256 public totalLotteryFees;

    uint256 public stakePool;

    function setStakePool(uint256 amount) external
    {
        stakePool = amount;
    }

    function addStakeFee(uint256 amount) external
    {
        totalStakeFees += amount;
    }

    function addLotteryFee(uint256 amount) external
    {
        totalLotteryFees += amount;
    }

    function isTaxExcluded(address account) external view returns(bool)
    {
        return _taxExclusions[account];
    }

    function setTaxExclusion(address account, bool value) external
    {
        _taxExclusions[account] = value;
    }

    function balanceOf(address account) external view returns (uint256)
    {
        return _balances[account];
    }

    function mint(address recipient, uint256 amount) external 
    {
        _balances[recipient] += amount;
    }

    function transfer(address sender, address recipient, uint256 amount) external 
    {
        _balances[sender] -= amount;
        _balances[recipient] += amount;
    }

    function allowance(address owner, address spender) external view returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address owner, address spender, uint256 amount) external
    {
        _allowances[owner][spender] = amount;
    } 
}