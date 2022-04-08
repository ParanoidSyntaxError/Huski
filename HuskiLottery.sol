// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LinkTokenInterface.sol";
import "./VRFConsumerBaseV2.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./HuskiSwap.sol";

contract HuskiLottery is HuskiSwap, VRFConsumerBaseV2
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

    mapping(address => TicketBalance) private _ticketBalances;
    mapping(uint256 => Ticket) public _tickets;
    uint256 public ticketHolderCount;
    uint256 public ticketCount;

    uint256 private _ticketThreshold = 100;
    uint256 public ticketPrice = 10**15; //0.001 BNB

    mapping (address => uint256) private _rewards;
    uint256 private _unclaimedRewards;
    
    uint256 private _lotteryStart;
    uint256 private _lotteryEnd;
    uint256 private _lotteryDuration = 7 days;

    // Chainlink
    VRFCoordinatorV2Interface private _vrfCoordinator;
    LinkTokenInterface private _linkToken;

    //TESTNET VALUES
    address public constant VRF_CONTRACT = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 private constant KEY_HASH = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint32 private _callbackGasLimit = 100000;
    uint16 private _requestConfirmations = 3;

    uint256 private _requestId;
    uint64 private _subscriptionId;

    uint256 private _vrfFee = 10**17; //0.1 LINK
    bool private _vrfLocked;

    uint256 private _vrfRandom;
    bool private _drawLottery;

    constructor(Huski huskiContract) HuskiSwap(huskiContract) VRFConsumerBaseV2(VRF_CONTRACT)
    {      
        _vrfCoordinator = VRFCoordinatorV2Interface(VRF_CONTRACT);
        _linkToken = LinkTokenInterface(LINK);

        //Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        _subscriptionId = _vrfCoordinator.createSubscription();

        //Add this contract as a consumer of its own subscription.
        _vrfCoordinator.addConsumer(_subscriptionId, consumers[0]);

        //Initialize lottery
        _restart();
    }

    //DEBUG - TESTNET ONLY
    function REQUEST_LOTTERY() external
    {
        _lotteryEnd = block.timestamp;
        _requestRandom();
    }

    //DEBUG - TESTNET ONLY
    function CHECK_LOTTERY() external
    {
        _lotteryEnd = block.timestamp;
        _checkLottery();
    }

    function lotteryPool() public view returns(uint256)
    {
        return _hski.balanceOf(address(this)) - (_unclaimedRewards + _hski.stakePool());
    }

    function vrfBalance() public view returns(uint256)
    {
        (uint96 subBalance,,,) = _vrfCoordinator.getSubscription(_subscriptionId);
        return subBalance;
    }

    function topUpVrfSubscription() external returns (bool)
    {
        _transferVrfLink();
        return true;
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override 
    {
        _vrfRandom = randomWords[0];
        _drawLottery = true;
    }

    function remainingLotteryTime() public view returns (uint256)
    {
        if(_lotteryEnd > block.timestamp)
        {
            return _lotteryEnd - block.timestamp;
        }

        return 0;
    }

    function ticketBalanceOf(address account) public view returns (uint256)
    {
        if(_ticketBalances[account].timestamp == _lotteryStart)
        {
            return _ticketBalances[account].amount;
        }

        return 0;
    }

    function unclaimedLotteryRewardsOf(address account) public view returns (uint256)
    {
        return _rewards[account];
    }

    function claimLotteryReward(address account) external returns (bool)
    {
        uint256 reward = _rewards[account];

        require(reward > 0);

        _rewards[account] -= reward;

        _unclaimedRewards = _unclaimedRewards - reward;

        _hski.rawTransfer(address(this), account, reward);

        if(address(this).balance > 0)
        {
            liquidityBuyBack();
        }

        return true;
    }

    function buyTickets() external payable returns (bool)
    {
        require(_lotteryFinished() == false);
        require(_vrfLocked == false);
        uint256 value = msg.value;
        require(value >= ticketPrice);

        address sender = msg.sender;
        uint256 ticketAmount = value / ticketPrice;

        uint256 ticketPacks = ticketAmount / _ticketThreshold;

        for(uint256 i = 0; i < ticketPacks + 1; i++)
        {
            _tickets[ticketCount + (i * (_ticketThreshold - 1))] = Ticket(_lotteryStart, sender);
        }

        _tickets[ticketCount + (ticketAmount - 1)] = Ticket(_lotteryStart, sender); 

        ticketCount += ticketAmount;

        if(_ticketBalances[sender].timestamp != _lotteryStart)
        {
            _ticketBalances[sender] = TicketBalance(_lotteryStart, ticketAmount);
            ticketHolderCount++;
        }
        else
        {
            _ticketBalances[sender].amount += ticketAmount;
        }

        emit TicketsBought(sender, ticketAmount);

        return true;
    }

    function _transferVrfLink() private
    {
        _linkToken.transferAndCall(address(_vrfCoordinator), _linkToken.balanceOf(address(this)), abi.encode(_subscriptionId));
    }

    function _refillVrf(uint256 bnbAmount, uint256 minLink) private
    {
        _swapBNBforLINK(bnbAmount, minLink, address(this));
        _transferVrfLink();
    }

    function _requestRandom() private 
    {
        //Will revert if subscription is not set and funded.
        _requestId = _vrfCoordinator.requestRandomWords(KEY_HASH, _subscriptionId, _requestConfirmations, _callbackGasLimit, 1); 
        _vrfLocked = true;
    }

    function _lotteryFinished() internal view returns (bool)
    {
        return (block.timestamp >= _lotteryEnd);
    }

    function _restart() private 
    {
        _lotteryStart = block.timestamp;
        _lotteryEnd = block.timestamp + _lotteryDuration;
        ticketCount = 0;
        ticketHolderCount = 0;
    }

    function _rollover() private
    {
        _lotteryEnd = block.timestamp + _lotteryDuration;

        emit LotteryRollover(lotteryPool());
    }

    function _checkLottery() internal returns (bool)
    {
        if(_drawLottery == true)
        {
            _draw(_vrfRandom);
            return true;
        }
        else
        {
            if(_vrfLocked == false && _lotteryFinished() == true)
            {
                uint256 vrfSubBalance = vrfBalance();

                if(vrfSubBalance < _vrfFee * 12)
                {
                    uint256 bnbSwapAmount = address(this).balance;

                    if(bnbSwapAmount > ticketPrice)
                    {
                        bnbSwapAmount = ticketPrice;
                    }

                    _refillVrf(bnbSwapAmount, 0);
                }

                if(ticketCount == 0 || lotteryPool() == 0 || vrfSubBalance < _vrfFee)
                {
                    _rollover();
                    return true;
                }
                else
                {
                    _requestRandom();
                    return true;
                }
            }   
        }

        return false;
    }

    function _draw(uint256 randomNumber) private
    {
        uint256 drawnTicket = randomNumber % ticketCount; //Random number within range

        address winner = address(this);

        if(_tickets[drawnTicket].timestamp != _lotteryStart)
        {
            for(uint256 i = 1; i < _ticketThreshold + 1; i++)
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

        uint256 reward = lotteryPool();

        _rewards[winner] += reward;
        _unclaimedRewards += reward;

        _restart();

        _vrfLocked = false;
        _drawLottery = false;

        emit LotteryAwarded(winner, reward);
    }
}