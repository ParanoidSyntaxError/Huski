// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFConsumerBaseV2.sol";
import "./LinkTokenInterface.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./HuskiStake.sol";

contract HuskiLottery is HuskiStake, VRFConsumerBaseV2
{
    struct Ticket
    {
        uint256 timestamp;
        address owner;
    }

    struct TicketBalance
    {
        uint256 timestamp;
        uint256 amount;
    }

    event TicketsBought(address indexed from, uint256 amount);
    event LotteryAwarded(address indexed to, uint256 value);
    event LotteryRollover(uint256 value);

    event LiquidityLocked(address indexed from, uint256 hskiValue, uint256 bnbValue, uint256 lpValue);

    mapping(address => TicketBalance) private _ticketBalances;
    mapping(uint256 => Ticket) private _tickets;
    uint256 private _holderCount;
    uint256 private _ticketCount;

    uint256 private _ticketThreshold = 100;
    uint256 private _thresholdReward = 1;
    uint256 private _ticketPrice = 10**16; //0.01 BNB

    mapping (address => uint256) private _rewards;
    uint256 private _unclaimedRewards;
    
    uint256 private _lotteryStart;
    uint256 private _lotteryEnd;
    uint256 private _lotteryDuration = 7 days;

    // Chainlink

    VRFCoordinatorV2Interface private _vrfCoordinator;
    LinkTokenInterface private _linkToken;

    //TESTNET VALUES
    address private _vrfContract = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    address private _linkContract = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
    bytes32 private _keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint32 private _callbackGasLimit = 100000;
    uint16 private _requestConfirmations = 3;

    uint256 private _requestId;
    uint64 private _subscriptionId;

    uint256 private _vrfFee = (10**15) * 5; //0.005 LINK
    bool private _vrfLocked;

    // Uniswap

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    address[] private _bnbToLINK;
    address[] private _bnbToHSKI;

    //TESTNET https://pancake.kiemtienonline360.com/#/swap
    address private constant _pancakeswapRouter = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; 

    address private _swapReceiver;

    uint256 private _hskiLocked;
    uint256 private _bnbLocked;

    mapping (address => uint256) _lpTokens;

    constructor() VRFConsumerBaseV2(_vrfContract)
    {      
        address sender = _msgSender();

        //Uniswap
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_pancakeswapRouter);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;

        //Uniswap routing paths
        //BNB -> LINK
        _bnbToLINK = new address[](2);
        _bnbToLINK[0] = _uniswapV2Router.WETH();
        _bnbToLINK[1] = _linkContract;

        //BNB -> HSKI
        _bnbToHSKI = new address[](2);
        _bnbToHSKI[0] = _uniswapV2Router.WETH();
        _bnbToHSKI[1] = address(this);

        //Set swap reciver to deployer address
        _swapReceiver = sender;

        //Chainlink
        _vrfCoordinator = VRFCoordinatorV2Interface(_vrfContract);
        _linkToken = LinkTokenInterface(_linkContract);

        //Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        _subscriptionId = _vrfCoordinator.createSubscription();
        //Add this contract as a consumer of its own subscription.
        _vrfCoordinator.addConsumer(_subscriptionId, consumers[0]);

        //Initialize lottery
        _restartLottery();
    }

    // Recieve BNB from Pancakeswap router when swaping
    receive() external payable { } 

    //TESTNET DEBUG
    function stopLottery() public returns (bool)
    {
        if(_vrfLocked == false)
        {
            if(_checkLotteryRollover() == false)
            {
                _requestRandomTicket();
            }

            return true;
        }

        return false;
    }

    /*
        Lottery functions
    */

    function lotteryPool() external view returns(uint256)
    {
        return _lotteryPool();
    }

    function ticketPrice() public view returns (uint256)
    {
        return _ticketPrice;
    }

    function remainingLotteryTime() public view returns (uint256)
    {
        return _lotteryEnd - block.timestamp;
    }

    function totalTicketsBought() public view returns (uint256)
    {
        return _ticketCount;
    }

    function totalTicketHolders() public view returns (uint256)
    {
        return _holderCount;
    }

    function ticketBalanceOf(address account) public view returns (uint256)
    {
        if(_ticketBalances[account].timestamp == _lotteryStart)
        {
            return _ticketBalances[account].amount;
        }

        return 0;
    }

    function unclaimedRewardsOf(address account) public view returns (uint256)
    {
        return _rewards[account];
    }

    function buyTickets() external payable returns (bool)
    {
        require(_lotteryFinished() == false);
        uint256 value = msg.value;
        require(value >= _ticketPrice);

        address sender = _msgSender();
        uint256 ticketAmount = value / _ticketPrice;

        uint256 ticketPacks = ticketAmount / _ticketThreshold;

        for(uint256 i = 0; i < ticketPacks + 1; i++)
        {
            _tickets[_ticketCount + (i * (_ticketThreshold + _thresholdReward))] = Ticket(_lotteryStart, sender);
        }

        _ticketCount += ticketAmount;

        if(_ticketBalances[sender].timestamp != _lotteryStart)
        {
            _ticketBalances[sender] = TicketBalance(_lotteryStart, ticketAmount);
            _holderCount++;
        }
        else
        {
            _ticketBalances[sender].amount += ticketAmount;
        }

        emit TicketsBought(sender, ticketAmount);

        return true;
    }

    function claimReward(address account) external returns (bool)
    {
        uint256 reward = _rewards[account];

        require(reward > 0);

        _transfer(address(this), account, reward);

        _unclaimedRewards = _unclaimedRewards - reward;

        if(address(this).balance > 0)
        {
            _lockLiquidity();
        }

        return true;
    }

    function checkLottery() external returns (bool)
    {
        require(_checkLottery() == true);
        return true;
    }

    function _lotteryPool() private view returns(uint256)
    {
        return balanceOf(address(this)) - (_unclaimedRewards + stakePool());
    }

    function _lotteryFinished() internal view returns (bool)
    {
        return (block.timestamp > _lotteryEnd);
    }

    function _restartLottery() private 
    {
        _lotteryStart = block.timestamp;
        _lotteryEnd = block.timestamp + _lotteryDuration;
        _ticketCount = 0;
        _holderCount = 0;
    }

    function _checkLottery() private returns (bool)
    {
        if(_lotteryFinished() == true && _vrfLocked == false)
        {
            if(_checkLotteryRollover() == false)
            {
                _requestRandomTicket();
            }

            return true;
        }

        return false;
    }

    function _checkLotteryRollover() private returns(bool)
    {
        (uint96 subBalance,,,) = _vrfCoordinator.getSubscription(_subscriptionId);

        if(subBalance < _vrfFee * 12)
        {
            _swapBNBforLINK(address(this).balance, _vrfFee * 100);
        }

        _topUpVRFSubscription(_linkToken.balanceOf(address(this)));

        (uint96 newSubBalance,,,) = _vrfCoordinator.getSubscription(_subscriptionId);

        if(_ticketCount == 0 || _lotteryPool() == 0 || newSubBalance < _vrfFee)
        {
            _lotteryEnd = block.timestamp + _lotteryDuration;

            emit LotteryRollover(_lotteryPool());
            return true;
        }

        return false;
    }

    function _drawLottery(uint256 randomNumber) private
    {
        uint256 drawnTicket = randomNumber % _ticketCount; //Random number within range

        address winner = address(this);

        if(_tickets[drawnTicket].timestamp != _lotteryStart)
        {
            for(uint256 i = 1; i < (_ticketThreshold + _thresholdReward) + 1; i++)
            {
                if(_tickets[drawnTicket - i].timestamp == _lotteryStart)
                {
                    winner = _tickets[drawnTicket - i].owner;
                    break;
                }
            }
        }
        else
        {
            winner = _tickets[drawnTicket].owner;
        }

        uint256 reward = _lotteryPool();

        _rewards[winner] += reward;
        _unclaimedRewards += reward;

        _restartLottery();

        _vrfLocked = false;

        emit LotteryAwarded(winner, reward);
    }

    /*
        Uniswap functions
    */

    function totalHskiLocked() public view returns (uint256)
    {
        return _hskiLocked;
    }

    function totalBnbLocked() public view returns (uint256)
    {
        return _bnbLocked;
    }

    function lockContractLiquidity() external returns (bool)
    {
        _lockLiquidity();

        return true;
    }

    //Tax free liquidity providing
    function addLiquidity(uint256 hskiAmount, uint256 minHski, uint256 minBnb) external payable returns (uint256, uint256, uint256)
    {
        address sender = msg.sender;
        uint256 bnbAmount = msg.value;

        require(_balances[sender] >= hskiAmount);
        require(bnbAmount > 0);
        require(hskiAmount > 0);

        _balances[sender] -= hskiAmount;

        (uint256 hskiSent, uint256 bnbSent, uint256 lpTokens) = _addLiquidity(hskiAmount, bnbAmount, minHski, minBnb, address(this));

        _lpTokens[sender] += lpTokens;

        //Return unused HSKI
        _balances[sender] += hskiAmount - hskiSent;

        //Return unused BNB
        (bool sent,) = sender.call{value: bnbAmount - bnbSent}("");
        require(sent == true);

        return (hskiSent, bnbSent, lpTokens);
    }

    //Tax free liquidity removal
    function removeLiquidity(uint256 lpTokens, uint256 minHski, uint256 minBnb) external returns (uint256, uint256)
    {
        address sender = msg.sender;

        require(lpTokens > 0);
        require(_lpTokens[sender] >= lpTokens);

        _taxExclusions[_pancakeswapRouter] = true;

        (uint256 hskiReceived, uint256 bnbReceived) = uniswapV2Router.removeLiquidityETH
        (
            address(this),  //Token address
            lpTokens,       //LP tokens to remove.
            minHski,        //Minimum HSKI
            minBnb,         //Minimum BNB
            sender,         //Recipient of tokens
            block.timestamp //Deadline
        );

        _taxExclusions[_pancakeswapRouter] = false;

        _lpTokens[sender] -= lpTokens;

        return (hskiReceived, bnbReceived);
    }

    //TODO: Return bool, debug swap
    //Tax free swaps
    function buyHSKI(uint256 minHski) external payable
    {
        address sender = msg.sender;
        uint256 value = msg.value;

        _swapBNBforHSKI(value, minHski, sender);
    }

    function _lockLiquidity() private
    {
        //Use all BNB in contract address
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);
        uint256 bnbAmount = contractBalance / 2;

        uint256 startingHskiAmount = _balances[_swapReceiver];

        //Swap BNB for HSKI
        _swapBNBforHSKI(bnbAmount, 0, _swapReceiver);

        uint256 hskiAmount = _balances[_swapReceiver] - startingHskiAmount;

        //Uniswap factory doesn't allow reciever to be token contract address
        _balances[_swapReceiver] -= hskiAmount;
        _balances[address(this)] += hskiAmount;

        //Add liquidity to uniswap
        (uint256 hskiAdded, uint256 bnbAdded, uint256 lpReceived) = _addLiquidity(hskiAmount, bnbAmount, 0, 0, address(this));

        _hskiLocked += hskiAdded;
        _bnbLocked += bnbAdded;

        emit LiquidityLocked(address(this), hskiAdded, bnbAdded, lpReceived);
    }

    //TODO: Debug swap - Should this function revert
    function _swapBNBforHSKI(uint256 bnbAmount, uint256 minHski, address receiver) private
    {
        //Swap BNB and recieve HSKI to contract address
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value : bnbAmount } //BNB value
        (
            minHski,        //Minimum HSKI
            _bnbToHSKI,     //Routing path
            receiver,       //Receiver (can't set recieve to token contract address)
            block.timestamp //Deadline
        );
    }

    //TODO: Debug swap - Should this function revert
    function _swapBNBforLINK(uint256 bnbAmount, uint256 linkAmount) private
    {
        //Swap BNB and recieve LINK to contract address 
        uniswapV2Router.swapETHForExactTokens{ value : bnbAmount } //BNB value
        (
            linkAmount,     //Minimum LINK
            _bnbToLINK,     //Routing path
            address(this),  //Receiver
            block.timestamp //Deadline
        );
    }

    function _addLiquidity(uint256 hskiAmount, uint256 bnbAmount, uint256 minHski, uint256 minBnb, address lpReceiver) private returns (uint256, uint256, uint256)
    {
        //Approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), hskiAmount);

        //Add liquidity to BNB/HSKI pool
        (uint hskiSent, uint bnbSent, uint lpTokens) = uniswapV2Router.addLiquidityETH{ value : bnbAmount } //BNB value
        (
            address(this),  //Token address
            hskiAmount,     //HSKI amount
            minHski,        //Minimum HSKI
            minBnb,         //Minimum BNB
            lpReceiver,     //LP token receiver
            block.timestamp //Deadline
        );

        return (hskiSent, bnbSent, lpTokens);
    }

    /*
        Chainlink functions
    */

    function _requestRandomTicket() internal 
    {
        //Will revert if subscription is not set and funded.
        _requestId = _vrfCoordinator.requestRandomWords(_keyHash, _subscriptionId, _requestConfirmations, _callbackGasLimit, 1); 
        _vrfLocked = true;
    }

    function fulfillRandomWords(uint256, uint256[] memory randomValues) internal override 
    {
        _drawLottery(randomValues[0]);
    }

    function _topUpVRFSubscription(uint256 amount) private 
    {
        _linkToken.transferAndCall(address(_vrfCoordinator), amount, abi.encode(_subscriptionId));
    }
}