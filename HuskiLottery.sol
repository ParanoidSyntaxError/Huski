// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VRFConsumerBaseV2.sol";
import "./LinkTokenInterface.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./HuskiSwap.sol";

contract HuskiLottery is VRFConsumerBaseV2
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
    address private constant VRF_CONTRACT = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 private constant KEY_HASH = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint32 private _callbackGasLimit = 100000;
    uint16 private _requestConfirmations = 3;

    uint256 private _requestId;
    uint64 private _subscriptionId;

    uint256 private _vrfFee = (10**15) * 5; //0.005 LINK
    bool private _vrfLocked;

    HuskiSwap private _swap;

    HuskiToken private _hski;

    constructor(HuskiToken token, HuskiSwap swap) VRFConsumerBaseV2(VRF_CONTRACT)
    {      
        _hski = token;
        _swap = swap;

        _vrfCoordinator = VRFCoordinatorV2Interface(VRF_CONTRACT);
        _linkToken = LinkTokenInterface(_swap.LINK());

        //Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        _subscriptionId = _vrfCoordinator.createSubscription();

        //Add this contract as a consumer of its own subscription.
        _vrfCoordinator.addConsumer(_subscriptionId, consumers[0]);

        //Initialize lottery
        _restartLottery();
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override 
    {
        _drawLottery(randomWords[0]);
    }

    function _requestRandom() internal 
    {
        //Will revert if subscription is not set and funded.
        _requestId = _vrfCoordinator.requestRandomWords(KEY_HASH, _subscriptionId, _requestConfirmations, _callbackGasLimit, 1); 
        _vrfLocked = true;
    }

    function _checkLottery() internal returns (bool)
    {
        if(_lotteryFinished() == true && _vrfLocked == false)
        {
            if(_checkLotteryRollover() == false)
            {
                _requestRandom();
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
            _swap.swapBNBforLINK(address(this).balance, 0, address(this));
        }

        //_topUpVRFSubscription(_linkToken.balanceOf(address(this)));

        (uint96 newSubBalance,,,) = _vrfCoordinator.getSubscription(_subscriptionId);

        if(_ticketCount == 0 || _lotteryPool() == 0 || newSubBalance < _vrfFee)
        {
            _lotteryEnd = block.timestamp + _lotteryDuration;

            emit LotteryRollover(_lotteryPool());
            return true;
        }

        return false;
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

    function _transferVrfLink() private
    {
        _linkToken.transferAndCall(address(_vrfCoordinator), _linkToken.balanceOf(address(this)), abi.encode(_subscriptionId));
    }

    function _refillVrf(uint256 bnbAmount, uint256 minLink) private
    {
        _swap.swapBNBforLINK(bnbAmount, minLink, address(this));
        _transferVrfLink();
    }



    function claimReward(address account) external returns (bool)
    {
        uint256 reward = _rewards[account];

        require(reward > 0);

        _rewards[account] -= reward;

        _unclaimedRewards = _unclaimedRewards - reward;

        _hski.transfer(address(this), account, reward);

        if(address(this).balance > 0)
        {
            _swap.lockLiquidity();
        }

        return true;
    }

    //TESTNET DEBUG
    function stopLottery() public returns (bool)
    {
        if(_vrfLocked == false)
        {
            if(_checkLotteryRollover() == false)
            {
                _requestRandom();
            }

            return true;
        }

        return false;
    }

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

        address sender = msg.sender;
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

    function checkLottery() external returns (bool)
    {
        require(_checkLottery() == true);
        return true;
    }

    function _lotteryPool() private view returns(uint256)
    {
        return _hski.balanceOf(address(this)) - (_unclaimedRewards + _hski.stakePool());
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
}