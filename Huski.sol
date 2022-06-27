// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./HuskiStake.sol";
import "./HuskiLottery.sol";

contract Huski is IERC20, IERC20Metadata, HuskiStake, HuskiLottery
{
    string private constant NAME = "Huski";
    string private constant SYMBOL = "HSKI";
    uint8 private constant DECIMALS = 18;

    uint256 private constant MAX_SUPPLY = (10**9) * (10**DECIMALS); //1 billion
    uint256 private _totalSupply;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 public constant STAKE_TAX = 2;
    uint256 public constant BURN_TAX = 1;
    uint256 public constant LOTTERY_TAX = 2;

    address public constant huskiPool = address(1);

    mapping (address => bool) public taxExclusions;

    constructor() HuskiStake(this) HuskiLottery(this)
    {
        taxExclusions[address(this)] = true;
        
        _totalSupply = MAX_SUPPLY;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(this), msg.sender, _totalSupply);
    }

    function name() public pure override returns (string memory) 
    {
        return NAME;
    }

    function symbol() public pure override returns (string memory) 
    {
        return SYMBOL;
    }

    function decimals() public pure override returns (uint8) 
    {
        return DECIMALS;
    }

    function totalSupply() public view override returns (uint256) 
    {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) 
    {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view override returns (uint256) 
    {
        return _allowances[owner][spender];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function totalBurn() public view returns (uint256)
    {
        return MAX_SUPPLY - _totalSupply;
    }

    function contractBurn() public returns (bool)
    {
        _burn(address(this), balanceOf(address(this)));
        return true;
    }

    function burn(uint256 amount) public returns (bool)
    {
        _burn(msg.sender, amount);
        return true;
    }

    function taxFreeTransfer(address sender, address recipient, uint256 amount) public
    {
        require(msg.sender == address(this));
        _balances[sender] -= amount;
        _balances[recipient] += amount;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, msg.sender);
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");

        unchecked 
        {
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) 
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) 
    {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) 
    {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");

        unchecked 
        {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function setTaxExclusion(address account, bool value) public
    {
        require(msg.sender == address(this));
        taxExclusions[account] = value;
    }

    function _taxValues(uint256 amount) internal pure returns(uint256, uint256, uint256)
    {
        return ((amount / 100) * STAKE_TAX, (amount / 100) * BURN_TAX, (amount / 100) * LOTTERY_TAX);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal
    {
        require(sender != address(0));
        require(recipient != address(0));

        uint256 transferAmount = amount;

        if(taxExclusions[sender] == false)
        {
            (uint256 stakeFee, uint256 burnFee, uint256 lotteryFee) = _taxValues(amount);

            uint256 totalFee = stakeFee + burnFee + lotteryFee;
         
            //Burn
            _burn(sender, burnFee);

            //Stake
            _stakeFee(stakeFee);

            //Lottery
            _lotteryFee(lotteryFee);

            taxFreeTransfer(sender, huskiPool, stakeFee + lotteryFee);

            transferAmount -= totalFee;
        }

        _balances[sender] -= transferAmount;
        _balances[recipient] += transferAmount;

        emit Transfer(sender, recipient, transferAmount);
    }

    function _burn(address account, uint256 amount) internal
    {
        _balances[account] -= amount;
        _totalSupply -= amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal
    {
        require(owner != address(0));
        require(spender != address(0));
        
        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }
}