// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LotteryNew
{
    struct TicketBalance
    {
        uint256 amount;
        address wallet;
    }

    mapping(address => uint256) private _addressIndexes;
    TicketBalance[] private _tickets;

    uint256 private _holderCount;
    uint256 private _ticketCount;

    address public lastWinner;

    function buyTickets(uint256 amount) public returns (bool)
    {
        address sender = msg.sender;

        if(_addressIndexes[sender] <= 0)
        {
            _addressIndexes[sender] = _holderCount;

            if(_ticketCount < _holderCount)
            {
                _tickets.push();

            } 
                        
            _holderCount += 1;
        }
        else
        {
            _tickets[_addressIndexes[sender]].amount += amount;
        }

        _ticketCount += amount;

        return true;
    }

    function drawTicket(uint256 ticket) public returns (bool)
    {
        require(ticket < _ticketCount);

        uint256 count = 0;

        //For each ticket purchased add senders address to tickets array
        for (uint256 i = 1; i < _holderCount + 1; i++) 
        {
            if(ticket < count + _tickets[i].amount)
            {
                //Winner
                lastWinner = _tickets[i].wallet;
                break;
            }

            count += _tickets[i].amount;
        }

        return true;
    }
}

contract LotteryOld
{
    struct TicketBalance
    {
        uint256 tickets;
        uint256 lotteryTime;
    }

    mapping(address => TicketBalance) internal _ticketBalances;
    address[] internal _tickets;
    uint256 internal _ticketCount;

    function buyTickets(uint256 amount) public returns (bool)
    {
        address sender = msg.sender;

        for (uint256 i = 0; i < amount; i++) 
        {
            if(_ticketCount + i >= _tickets.length)
            {
                _tickets.push(sender);
            }
            else
            {
                _tickets[_ticketCount + i] = sender;
            }
        }

        _ticketCount = _ticketCount + amount;

        _ticketBalances[sender].tickets += amount;

        return true;
    }

    function drawTicket(uint256 ticket) public returns (bool)
    {
        
        return true;
    }
}