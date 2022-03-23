// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./HuskiToken.sol";
import "./HuskiSwap.sol";
import "./HuskiStake.sol";
import "./HuskiLottery.sol";

contract Huski is IERC20, IERC20Metadata, HuskiStake, HuskiLottery
{
    address public constant BURN_WALLET = 0x000000000000000000000000000000000000dEaD;

    HuskiToken private _hski = new HuskiToken();

    HuskiSwap private _swap = new HuskiSwap(_hski);

    constructor() HuskiStake(_hski) HuskiLottery(_hski, _swap)
    {
        address sender = msg.sender;

        _hski.setTaxExclusion(address(this), true);

        _hski.mint(sender, _hski.TOTAL_SUPPLY());
        emit Transfer(address(this), sender, _hski.TOTAL_SUPPLY());
    }   

    function name() public view override returns (string memory) 
    {
        return _hski.NAME();
    }

    function symbol() public view override returns (string memory) 
    {
        return _hski.SYMBOL();
    }

    function decimals() public view override returns (uint8) 
    {
        return _hski.DECIMALS();
    }

    function totalSupply() public view override returns (uint256) 
    {
        return _hski.TOTAL_SUPPLY();
    }

    function balanceOf(address account) public view override returns (uint256) 
    {
        return _hski.balanceOf(account);
    }

    function totalBurn() public view returns (uint256)
    {
        return _hski.balanceOf(BURN_WALLET);
    }

    function totalStakeFees() public view returns (uint256) 
    {
        return _hski.totalStakeFees();
    }

    function totalLotteryFees() public view returns (uint256)
    {
        return _hski.totalLotteryFees();
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) 
    {
        return _hski.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) public override returns (bool) 
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _hski.allowance(sender, msg.sender);
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");

        unchecked 
        {
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) 
    {
        _hski.approve(msg.sender, spender, _hski.allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) 
    {
        uint256 currentAllowance = _hski.allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");

        unchecked 
        {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transferValues(uint256 amount) private view returns (uint256)
    {
        return amount - ((amount / 100) * (_hski.STAKE_TAX() + _hski.BURN_TAX() + _hski.LOTTERY_TAX()));
    }

    function _taxValues(uint256 amount) private view returns(uint256, uint256, uint256)
    {
        return ((amount / 100) * _hski.STAKE_TAX(), (amount / 100) * _hski.BURN_TAX(), (amount / 100) * _hski.LOTTERY_TAX());
    }

    function _transfer(address sender, address recipient, uint256 amount) internal 
    {
        require(sender != address(0));
        require(recipient != address(0));
        require(amount > 0);
        require(_hski.balanceOf(sender) >= amount);

        _checkLottery();

        uint256 transferAmount = amount;

        if(_hski.isTaxExcluded(sender) == false)
        {
            (uint256 stakeAmount, uint256 burnAmount, uint256 lotteryAmount) = _taxValues(amount);

            _hski.transfer(sender, address(this), stakeAmount + lotteryAmount);
            _hski.transfer(sender, BURN_WALLET, burnAmount);

            _stakeFee(stakeAmount);

            _hski.addStakeFee(stakeAmount);
            _hski.addLotteryFee(lotteryAmount);

            transferAmount = _transferValues(amount);
        }

        _hski.transfer(sender, recipient, transferAmount);

        emit Transfer(sender, recipient, transferAmount);
    }

    function _approve(address owner, address spender, uint256 amount) internal 
    {
        require(owner != address(0));
        require(spender != address(0));
        
        _hski.approve(owner, spender, amount);

        emit Approval(owner, spender, amount);
    }
}