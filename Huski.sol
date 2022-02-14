// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Lottery.sol";
import "./Uniswap.sol";

// Utilities
library Address 
{
    function isContract(address account) internal view returns (bool) 
    {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal 
    {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) 
    {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) 
    {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) 
    {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) 
    {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) 
    {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) 
    {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) 
    {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) 
    {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) 
    {
        if (success) 
        {
            return returndata;
        } 
        else 
        {
            if (returndata.length > 0) 
            {
                assembly 
                {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } 
            else 
            {
                revert(errorMessage);
            }
        }
    }
}

abstract contract Context 
{
    function _msgSender() internal view virtual returns (address) 
    {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) 
    {
        this;
        return msg.data;
    }
}

abstract contract Ownable is Context 
{
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () 
    {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view virtual returns (address) 
    {
        return _owner;
    }

    modifier onlyOwner() 
    {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner 
    {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner 
    {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ERC20 standards
interface IERC20 
{
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 
{
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

// Huski token
contract Huski is IERC20, IERC20Metadata, Lottery, Context, Ownable
{
    // Libraries
    using Address for address;

    mapping (address => uint256) private _tOwned;
    mapping (address => uint256) private _rOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _reflectExclusions;
    mapping (address => bool) private _taxExclusions;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _tTotal;
    uint256 private _rTotal;

    address private _swapReceiver;
    address private _burnWallet;

    uint256 private _tReflectTotal;
    uint256 private _tLotteryTotal;

    uint256 private _hskiLocked;
    uint256 private _bnbLocked;
    
    uint256 private constant _burnTax = 1;
    uint256 private constant _reflectTax = 1;
    uint256 private constant _lotteryTax = 3;

    uint256 private constant MAX = ~uint256(0);

    // Uniswap
    event LiquidityLocked(address indexed from, uint256 hskiValue, uint256 bnbValue, uint256 lpValue);

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    address[] private _bnbToLINK;
    address[] private _bnbToHSKI;

    address private constant _pancakeswapRouter = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; //TESTNET https://pancake.kiemtienonline360.com/#/swap
                                                    //0x10ED43C718714eb63d5aA57B78B54704E256024E - MAINNET https://pancakeswap.finance/swap

    address private constant _linkToken = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;       //TESTNET
                                            //0x404460C6A5EdE2D891e8297795264fDe62ADBB75 - MAINNET

    address private constant _vrfCoordinator = 0xa555fC018435bef5A13C6c6870a9d4C11DEC329C;  //TESTNET
                                                //0x747973a5A2a4Ae1D3a8fDF5479f1514F65Db9C31 - MAINNET

    bytes32 private constant _vrfHash = 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186; //TESTNET
                                        //0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c - MAINNET

    constructor() VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        address sender = _msgSender();

        //Set token values
        _name = "Huski";
        _symbol = "HSKI";
        _decimals = 18;

        _swapReceiver = sender;
        _burnWallet = 0x000000000000000000000000000000000000dEaD;

        _tTotal = (10**9) * (10**_decimals); //1 billion
        _rTotal = (MAX - (MAX % _tTotal));

        //Supply sent to contract deployer
        _tOwned[sender] = _tTotal;
        emit Transfer(address(this), sender, _tTotal);

        //Setup lottery
        _vrfFee = (10**17) * 2; //0.2 LINK
        _vrfKeyHash = _vrfHash;

        _ticketPrice = 10**15; //0.001 BNB
        _lotteryWallet = address(this);

        _restartLottery();

        //Uniswap router values
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_pancakeswapRouter);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;

        //Uniswap routing paths
        //BNB -> LINK
        _bnbToLINK = new address[](2);
        _bnbToLINK[0] = _uniswapV2Router.WETH();
        _bnbToLINK[1] = _linkToken;

        //BNB -> HSKI
        _bnbToHSKI = new address[](2);
        _bnbToHSKI[0] = _uniswapV2Router.WETH();
        _bnbToHSKI[1] = address(this);

        //Addresses excluded from transfer tax
        _taxExclusions[address(this)] = true;
        _taxExclusions[_swapReceiver] = true;

        //Addresses excluded from reflection
        _reflectExclusions[address(this)] = true;
        _reflectExclusions[_swapReceiver] = true;
        _reflectExclusions[_burnWallet] = true;
        _reflectExclusions[_pancakeswapRouter] = true;
        //_reflectExclusions[uniswapV2Pair] = true; Set from function after deployment
    }   

    // Recieve BNB from Pancakeswap router when swaping
    receive() external payable { } 

    /*
        Uniswap methods
    */

    function _lockLiquidity() private
    {
        //Use all BNB in contract address
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);
        uint256 bnbAmount = contractBalance / 2;

        uint256 tStartingHskiAmount = _tOwned[_swapReceiver];

        //Swap BNB for HSKI
        _swapBNBforHSKI(bnbAmount);

        uint256 tHskiAmount = _tOwned[_swapReceiver] - tStartingHskiAmount;

        //Uniswap factory doesn't allow reciever to be token contract address
        _tOwned[_swapReceiver] -= tHskiAmount;
        _tOwned[address(this)] += tHskiAmount;

        //Add liquidity to uniswap
        (uint256 hskiAdded, uint256 bnbAdded, uint256 lpReceived) = _addLiquidity(tHskiAmount, bnbAmount);

        _hskiLocked += hskiAdded;
        _bnbLocked += bnbAdded;

        emit LiquidityLocked(address(this), hskiAdded, bnbAdded, lpReceived);
    }

    function _swapBNBforHSKI(uint256 bnbAmount) private
    {
        //Swap BNB and recieve HSKI to contract address
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value : bnbAmount } //BNB value
        (
            0,              //Minimum HSKI
            _bnbToHSKI,     //Routing path
            _swapReceiver,  //Receiver (can't set recieve to token contract address)
            block.timestamp //Deadline
        );
    }

    function _swapBNBforLINK(uint256 bnbAmount, uint256 linkAmount) private
    {
        //Swap BNB and recieve LINK to contract address 
        uniswapV2Router.swapETHForExactTokens{ value : bnbAmount } //BNB value
        (
            linkAmount,     //Exact LINK
            _bnbToLINK,     //Routing path
            address(this),  //Receiver
            block.timestamp //Deadline
        );
    }

    function _addLiquidity(uint256 hskiAmount, uint256 bnbAmount) private returns (uint256, uint256, uint256)
    {
        //Approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), hskiAmount);

        //Add liquidity to BNB/HSKI pool
        return uniswapV2Router.addLiquidityETH{ value : bnbAmount } //BNB value
        (
            address(this),  //Token address
            hskiAmount,     //HSKI amount
            0,              //Minimum HSKI
            0,              //Minimum BNB
            address(this),  //LP token receiver
            block.timestamp //Deadline
        );
    }

    /*
        Lottery methods
    */

    // DEBUG METHOD
    function stopLottery() public onlyOwner returns (bool)
    {
        if(_ticketCount == 0 || lotteryPool() == 0)
        {
            _restartLottery();

            emit LotteryRollover(lotteryPool());
            return true;
        }
        else
        {
            if(LINK.balanceOf(address(this)) < _vrfFee)
            {
                _swapBNBforLINK(address(this).balance, _vrfFee);
            }

            requestRandomTicket();
        }

        return true;
    }

    function lotteryPool() public view override returns(uint256)
    {
        return balanceOf(_lotteryWallet) - _tUnclaimedRewards;
    }

    function buyTickets() public payable override returns (bool)
    {
        require(_lotteryFinished() == false);
        uint256 value = msg.value;
        require(value >= _ticketPrice);

        address sender = _msgSender();
        uint256 senderIndex = _holderIndexes[sender];
        uint256 ticketAmount = value / _ticketPrice;

        if(_ticketBalances[senderIndex].timestamp != _lotteryStart)
        {
            _holderIndexes[sender] = _holderCount;

            _ticketBalances[_holderCount] = TicketBalance(ticketAmount, _lotteryStart, sender);

            _holderCount += 1;
        }
        else
        {
            _ticketBalances[senderIndex].balance += ticketAmount;
        }

        _ticketCount += ticketAmount;

        emit TicketsBought(sender, ticketAmount);

        return true;
    }

    function claimReward(address account) public override returns (bool)
    {
        _claimReward(account);
        return true;
    }

    function checkLottery() public returns (bool)
    {
        require(_lotteryFinished());
        require(_vrfLocked == false);
        _checkLottery();
        return true;
    }

    function setVrfFee(uint256 value) public onlyOwner returns(bool)
    {
        _vrfFee = value;
        return true;
    }

    function _checkLottery() internal override
    {
        if(_lotteryFinished() && _vrfLocked == false)
        {
            if(_lotteryRollover() == false)
            {
                requestRandomTicket();
            }
        }
    }

    function _lotteryRollover() internal override returns(bool)
    {
        if(LINK.balanceOf(address(this)) < _vrfFee)
        {
            _swapBNBforLINK(address(this).balance, _vrfFee);
        }

        if(_ticketCount == 0 || lotteryPool() == 0 || LINK.balanceOf(address(this)) < _vrfFee)
        {
            _lotteryDuration += 7 days;

            emit LotteryRollover(lotteryPool());
            return true;
        }

        return false;
    }

    //Called by Lottery.fulfillRandomness()
    function _drawLottery(uint256 randomNumber) internal override
    {
        uint256 drawnTicket = randomNumber % _ticketCount; //Random number within range

        address winner = address(this);
        uint256 ticketSum = 0;

        for (uint256 i = 0; i < _holderCount; i++) 
        {
            ticketSum += _ticketBalances[i].balance;

            if(drawnTicket < ticketSum)
            {
                //Winner
                winner = _ticketBalances[i].owner;
                break;
            }
        }

        uint256 tLotteryPool = lotteryPool();

        _tRewards[winner] += tLotteryPool;

        _tUnclaimedRewards += tLotteryPool;

        _restartLottery();

        _vrfLocked = false;

        emit LotteryAwarded(winner, tLotteryPool);
    }

    function _claimReward(address account) internal override
    {
        uint256 tReward = _tRewards[account];

        require(tReward > 0);

        _transfer(_lotteryWallet, account, tReward);

        _tUnclaimedRewards = _tUnclaimedRewards - tReward;

        _tLotteryTotal = _tLotteryTotal + tReward;

        if(address(this).balance > 0)
        {
            _lockLiquidity();
        }
    }

    /*
        Token methods
    */

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
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) 
    {
        if(_reflectExclusions[account])
        {
            return _tOwned[account];
        }

        return _tokenFromReflection(_rOwned[account]);
    }

    function totalReflection() public view returns (uint256) 
    {
        return _tReflectTotal;
    }

    function totalBurn() public view returns (uint256)
    {
        return balanceOf(_burnWallet);
    }

    function totalLotteryRewards() public view returns (uint256)
    {
        return _tLotteryTotal;
    }

    function totalHskiLocked() public view returns (uint256)
    {
        return _hskiLocked;
    }

    function totalBnbLocked() public view returns (uint256)
    {
        return _bnbLocked;
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

    function excludeFromReflection(address account) external onlyOwner()
    {
        require(_reflectExclusions[account] == false);

        _tOwned[account] = _tokenFromReflection(_rOwned[account]);

        _reflectExclusions[account] = true;
    }

    function includeInReflection(address account) external onlyOwner()
    {
        require(_reflectExclusions[account] == true);

        _rOwned[account] = _reflectionFromToken(_tOwned[account]);

        _reflectExclusions[account] = false;
    }

    function excludeFromTax(address account) external onlyOwner()
    {
        require(_taxExclusions[account] == false);

        _taxExclusions[account] = true;
    }

    function includeInTax(address account) external onlyOwner()
    {
        require(_taxExclusions[account] == true);

        _taxExclusions[account] = false;
    }

    function _tokenFromReflection(uint256 rAmount) private view returns(uint256) 
    {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount / currentRate; //tAmount
    }

    function _reflectionFromToken(uint256 tAmount) private view returns(uint256) 
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        uint256 currentRate = _getRate();
        return tAmount * currentRate; //rAmount
    }

    function _reflectFee(uint256 rReflect, uint256 tReflect) private 
    {
        _rTotal -= rReflect;
        _tReflectTotal += tReflect;
    }

    function _burnFee(uint256 rBurn, uint256 tBurn) private
    {
        if(_reflectExclusions[_burnWallet])
        {
            _tOwned[_burnWallet] += tBurn;
        }
        else
        {
            _rOwned[_burnWallet] += rBurn;
        }
    }

    function _lotteryFee(uint256 rLottery, uint256 tLottery) private
    {
        if(_reflectExclusions[_lotteryWallet])
        {
            _tOwned[_lotteryWallet] += tLottery;
        }
        else
        {
            _rOwned[_lotteryWallet] += rLottery;
        }
    }

    function _transferValues(uint256 tAmount) private view returns (uint256, uint256, uint256)
    {
        uint256 currentRate = _getRate();

        uint256 rAmount = tAmount * currentRate;

        uint256 tTax = (tAmount / 100) * (_reflectTax + _burnTax + _lotteryTax);
        uint256 rTax = tTax * currentRate;

        uint256 tTransferAmount = tAmount - tTax;
        uint256 rTransferAmount = rAmount - rTax;

        return(rAmount, rTransferAmount, tTransferAmount);
    }

    function _taxValues(uint256 tAmount) private view returns(uint256, uint256, uint256, uint256, uint256, uint256)
    {
        uint256 currentRate = _getRate();

        uint256 tReflect = (tAmount / 100) * _reflectTax;
        uint256 tBurn = (tAmount / 100) * _burnTax;
        uint256 tLottery = (tAmount / 100) * _lotteryTax;

        uint256 rReflect = tReflect * currentRate;
        uint256 rBurn = tBurn * currentRate;
        uint256 rLottery = tLottery * currentRate;

        return (rReflect, tReflect, rBurn, tBurn, rLottery, tLottery);
    }

    function _getRate() private view returns(uint256) 
    {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) 
    {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      

        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        {
            return (rSupply, tSupply);
        }
    }

    function _transfer(address sender, address recipient, uint256 tAmount) private 
    {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(tAmount > 0, "Transfer amount must be greater than zero");

        uint256 rAmount = _reflectionFromToken(tAmount);

        uint256 rTransferAmount = rAmount;
        uint256 tTransferAmount = tAmount;

        if(_taxExclusions[sender] == false)
        {
            (, rTransferAmount, tTransferAmount) = _transferValues(tAmount);
            (uint256 rReflect, uint256 tReflect, uint256 rBurn, uint256 tBurn, uint256 rLottery, uint256 tLottery) = _taxValues(tAmount);

            _reflectFee(rReflect, tReflect);
            _burnFee(rBurn, tBurn);
            _lotteryFee(rLottery, tLottery);
        }

        if(_reflectExclusions[sender])
        {
            if(_reflectExclusions[recipient])
            {
                //Both excluded
                _tOwned[sender] -= tTransferAmount;
                _tOwned[recipient] += tTransferAmount;
            }
            else
            {
                //Sender excluded
                _tOwned[sender] -= tTransferAmount;
                _rOwned[recipient] += rTransferAmount;
            }
        }
        else
        {
            if(_reflectExclusions[recipient])
            {
                //Recipient excluded
                _rOwned[sender] -= rTransferAmount;
                _tOwned[recipient] += tTransferAmount;
            }
            else
            {
                //None excluded
                _rOwned[sender] -= rTransferAmount;
                _rOwned[recipient] += rTransferAmount;
            }
        }

        _checkLottery();

        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _approve(address owner, address spender, uint256 amount) private 
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }
}