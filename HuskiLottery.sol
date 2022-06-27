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

    mapping(address => TicketBalance) private _ticketBalances;
    mapping(uint256 => Ticket) private _tickets;
    uint256 public ticketHolderCount;
    uint256 public ticketCount;

    uint256 private _ticketThreshold = 100;
    uint256 public ticketPrice = 10**15; //0.001 BNB

    mapping (address => uint256) private unclaimedWinnings;
    uint256 public totalUnclaimedWinnings;
    
    uint256 public lotteryStart;
    uint256 public lotteryEnd;
    uint256 private constant _lotteryDuration = 7 days;

    VRFCoordinatorV2Interface public vrfCoordinator;
    LinkTokenInterface public linkToken;

    //TESTNET VALUES
    address private constant VRF_CONTRACT = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    address private constant LINK_TOKEN = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
    bytes32 private constant KEY_HASH = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    uint256 private _requestId;
    uint64 private _subscriptionId;

    uint256 private _vrfFee = 10**17; //0.1 LINK
    bool private _vrfLocked;

    uint256 private _vrfResponse;
    bool private _drawLottery;

    uint256 public lotteryPool;

    uint256 public totalLotteryWinnings;

    constructor(Huski huskiContract) HuskiSwap(huskiContract) VRFConsumerBaseV2(VRF_CONTRACT)
    {      
        vrfCoordinator = VRFCoordinatorV2Interface(VRF_CONTRACT);
        linkToken = LinkTokenInterface(LINK_TOKEN);

        //Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        _subscriptionId = vrfCoordinator.createSubscription();

        //Add this contract as a consumer of its own subscription.
        vrfCoordinator.addConsumer(_subscriptionId, consumers[0]);

        //Initialize lottery
        _restart();
    }

    //DEBUG - TESTNET ONLY !!!!!!!!!!!!!!!!!!!!!!!!
    function END_LOTTERY() external
    {
        lotteryEnd = block.timestamp;
    }
    
    /* Lottery functions */

    function ticketBalanceOf(address account) public view returns (uint256)
    {
        if(_ticketBalances[account].timestamp == lotteryStart)
        {
            return _ticketBalances[account].amount;
        }

        return 0;
    }

    function buyTickets() external payable returns (bool)
    {
        require(_vrfLocked == false);
        require(msg.value >= ticketPrice);

        //Check draw
        _drawWinner();

        uint256 ticketAmount = msg.value / ticketPrice;

        uint256 ticketPacks = ticketAmount / _ticketThreshold;

        for(uint256 i = 0; i < ticketPacks + 1; i++)
        {
            _tickets[ticketCount + (i * (_ticketThreshold - 1))] = Ticket(lotteryStart, msg.sender);
        }

        _tickets[ticketCount + (ticketAmount - 1)] = Ticket(lotteryStart, msg.sender); 

        ticketCount += ticketAmount;

        if(_ticketBalances[msg.sender].timestamp != lotteryStart)
        {
            _ticketBalances[msg.sender] = TicketBalance(lotteryStart, ticketAmount);
            ticketHolderCount++;
        }
        else
        {
            _ticketBalances[msg.sender].amount += ticketAmount;
        }

        //Check VRF
        _requestWinner();

        return true;
    }

    function claimLotteryWinnings(address account) external returns (bool)
    {
        uint256 winnings = unclaimedWinnings[account];

        require(winnings > 0);

        unclaimedWinnings[account] -= winnings;
        totalUnclaimedWinnings -= winnings;

        _hski.taxFreeTransfer(_hski.huskiPool(), account, winnings);

        if(address(this).balance > 0)
        {
            liquidityBurn();
        }

        return true;
    }

    function requestWinner() external returns (bool)
    {
        require(_requestWinner());
        return true;
    }

    function drawWinner() external returns (bool)
    {
        require(_drawWinner());
        return true;
    }

    /* VRF functions */

    function transferContractLINKToVRF() public returns (bool)
    {
        linkToken.transferAndCall(address(vrfCoordinator), linkToken.balanceOf(address(this)), abi.encode(_subscriptionId));
        return true;
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override 
    {
        _vrfResponse = randomWords[0];
        _drawLottery = true;
    }

    /* Lottery functions */

    function _lotteryFee(uint256 amount) internal
    {
        lotteryPool += amount;
        totalLotteryWinnings += amount;
    }

    function _requestWinner() private returns (bool)
    {
        if(_vrfLocked == false && block.timestamp >= lotteryEnd)
        {
            if(_vrfSubscriptionBalance() < _vrfFee * 12)
            {
                _fundVRF();
            }

            if(ticketCount == 0 || lotteryPool == 0 || _vrfSubscriptionBalance() < _vrfFee)
            {
                _rollover();
            }
            else
            {
                _VRFRequest();
            }

            return true;
        }

        return false;
    }

    function _drawWinner() private returns (bool)
    {
        if(_drawLottery == true)
        {
            uint256 drawnTicket = _vrfResponse % ticketCount; //Random number within range

            address winner = address(this);

            if(_tickets[drawnTicket].timestamp != lotteryStart)
            {
                for(uint256 i = 1; i < _ticketThreshold + 1; i++)
                {
                    if(_tickets[drawnTicket - i].timestamp == lotteryStart)
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

            uint256 winnings = lotteryPool;

            unclaimedWinnings[winner] += winnings;
            totalUnclaimedWinnings += winnings;

            _restart();

            _vrfLocked = false;
            _drawLottery = false;

            return true;
        }

        return false;
    }

    function _rollover() private
    {
        lotteryEnd = block.timestamp + _lotteryDuration;
    }

    function _restart() private 
    {
        lotteryStart = block.timestamp;
        lotteryEnd = block.timestamp + _lotteryDuration;
        ticketCount = 0;
        ticketHolderCount = 0;

        lotteryPool = 0;
    }

    /* VRF functions */

    function _vrfSubscriptionBalance() private view returns(uint256)
    {
        (uint96 balance,,,) = vrfCoordinator.getSubscription(_subscriptionId);
        return balance;
    }

    function _VRFRequest() private 
    {
        //Will revert if subscription is not set and funded.
        _requestId = vrfCoordinator.requestRandomWords(KEY_HASH, _subscriptionId, 3, 100000, 1); 
        _vrfLocked = true;
    }

    function _fundVRF() private
    {
        uint256 bnbAmount = 10**17;

        if(bnbAmount > address(this).balance)
        {
            bnbAmount = address(this).balance;
        }

        _swapBNBforToken(bnbAmount, 0, LINK_TOKEN, address(this));        

        transferContractLINKToVRF();
    }
}