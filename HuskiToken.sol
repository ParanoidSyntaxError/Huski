// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";

contract HuskiToken is IERC20, IERC20Metadata, Ownable
{
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    string private _name = "Huski";
    string private _symbol = "HSKI";
    uint8 private _decimals = 18;

    uint256 internal _totalSupply = (10**9) * (10**_decimals); //1 billion

    uint256 private constant _stakeTax = 2;
    uint256 private constant _burnTax = 1;
    uint256 private constant _lotteryTax = 2;

    uint256 internal _totalStakeFees;
    uint256 internal _totalLotteryFees;

    address internal _contractAddress = address(this);
    address internal _burnWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 internal _stakePool;

    function _stakeFee(uint256 amount) internal virtual {}

    constructor()
    {
        address sender = _msgSender();

        //Supply sent to contract deployer
        _balances[sender] = _totalSupply;
        emit Transfer(address(this), sender, _totalSupply);
    }   

    function name() public view override returns (string memory) 
    {
        return _name;
    }

    function symbol() public view override returns (string memory) 
    {
        return _symbol;
    }

    function decimals() public view override returns (uint8) 
    {
        return _decimals;
    }

    function burnWallet() public view returns (address)
    {
        return _burnWallet;
    }

    function totalSupply() public view override returns (uint256) 
    {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) 
    {
        return _balances[account];
    }

    function totalBurn() public view returns (uint256)
    {
        return balanceOf(_burnWallet);
    }

    function totalStakeFees() public view returns (uint256) 
    {
        return _totalStakeFees;
    }

    function totalLotteryFees() public view returns (uint256)
    {
        return _totalLotteryFees;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) 
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) 
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) 
    {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");

        unchecked 
        {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) 
    {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) 
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");

        unchecked 
        {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transferValues(uint256 amount) private pure returns (uint256)
    {
        return amount - ((amount / 100) * (_stakeTax + _burnTax + _lotteryTax));
    }

    function _taxValues(uint256 amount) private pure returns(uint256, uint256, uint256)
    {
        return ((amount / 100) * _stakeTax, (amount / 100) * _burnTax, (amount / 100) * _lotteryTax);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal 
    {
        require(sender != address(0));
        require(recipient != address(0));
        require(amount > 0);

        uint256 transferAmount = _transferValues(amount);
        (uint256 stakeAmount, uint256 burnAmount, uint256 lotteryAmount) = _taxValues(amount);

        _totalStakeFees += stakeAmount;
        _balances[_contractAddress] += stakeAmount;
        _stakeFee(stakeAmount);
                
        _balances[_burnWallet] += burnAmount;

        _totalLotteryFees += lotteryAmount;
        _balances[_contractAddress] += lotteryAmount;

        _balances[sender] -= amount;
        _balances[recipient] += transferAmount;

        emit Transfer(sender, recipient, transferAmount);
    }

    function _approve(address owner, address spender, uint256 amount) internal 
    {
        require(owner != address(0));
        require(spender != address(0));
        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }
}