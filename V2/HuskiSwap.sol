// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./HuskiToken.sol";

contract HuskiSwap
{
    event LiquidityLocked(address indexed from, uint256 hskiValue, uint256 bnbValue, uint256 lpValue);

    //TESTNET: https://pancake.kiemtienonline360.com/#/swap
    address private constant SWAP_ROUTER = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; 

    //TESTNET
    address public constant LINK = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;

    address[] private _bnbToLINK;
    address[] private _bnbToHSKI;

    address private _swapReceiver;

    uint256 private _hskiLocked;
    uint256 private _bnbLocked;

    mapping (address => uint256) private _lpTokens;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    HuskiToken private _hski;

    constructor(HuskiToken token)
    {      
        _hski = token;

        address sender = msg.sender;

        //Set swap reciver to deployer address
        _swapReceiver = sender;

        //Uniswap initialization
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(SWAP_ROUTER);
        uniswapV2Pair = IUniswapV2Factory(swapRouter.factory()).createPair(address(this), swapRouter.WETH());
        uniswapV2Router = swapRouter;

        //Uniswap routing paths
        _bnbToLINK = [swapRouter.WETH(), LINK];
        _bnbToHSKI = [swapRouter.WETH(), address(this)];
    }

    // Recieve BNB from Pancakeswap router when swaping
    receive() external payable { } 

    function totalHskiLocked() external view returns (uint256)
    {
        return _hskiLocked;
    }

    function totalBnbLocked() external view returns (uint256)
    {
        return _bnbLocked;
    }

    //Tax free BNB=>HSKI swap
    function buyHSKI(uint256 minHski) external payable returns (bool)
    {
        address sender = msg.sender;
        uint256 value = msg.value;

        _hski.setTaxExclusion(uniswapV2Pair, true);

        swapBNBforHSKI(value, minHski, sender);

        _hski.setTaxExclusion(uniswapV2Pair, false);

        return true;
    }

    function swapBNBforHSKI(uint256 bnbAmount, uint256 minHski, address receiver) public
    {
        //Swap BNB and recieve HSKI to contract address
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value : bnbAmount } //BNB value
        (
            minHski,        //Minimum HSKI
            _bnbToHSKI,     //Routing path
            receiver,       //Receiver (can't set reciever to token address)
            block.timestamp //Deadline
        );
    }

    function swapBNBforLINK(uint256 bnbAmount, uint256 minLink, address receiver) public
    {
        //Swap BNB and recieve LINK to contract address 
        uniswapV2Router.swapExactETHForTokens{ value : bnbAmount } //BNB value
        (
            minLink,        //Minimum LINK
            _bnbToLINK,     //Routing path
            receiver,       //Receiver
            block.timestamp //Deadline
        );
    }

    function _addLiquidity(uint256 hskiAmount, uint256 bnbAmount, uint256 minHski, uint256 minBnb, address lpReceiver) private returns (uint256, uint256, uint256)
    {
        //Approve token transfer to cover all possible scenarios
        _hski.approve(address(this), address(uniswapV2Router), hskiAmount);

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

    //Tax free liquidity providing
    function addLiquidity(uint256 hskiAmount, uint256 minHski, uint256 minBnb) external payable returns (uint256, uint256, uint256)
    {
        address sender = msg.sender;
        uint256 bnbAmount = msg.value;

        require(bnbAmount > 0);
        require(hskiAmount > 0);
        require(_hski.balanceOf(sender) >= hskiAmount);

        //Transfer HSKI to contract
        _hski.transfer(sender, address(this), hskiAmount);

        //Add liquidity from contract
        (uint256 hskiSent, uint256 bnbSent, uint256 lpTokens) = _addLiquidity(hskiAmount, bnbAmount, minHski, minBnb, address(this));

        //Credit LP tokens
        _lpTokens[sender] += lpTokens;

        //Return unused HSKI
        _hski.transfer(address(this), sender, hskiAmount - hskiSent);

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

        _lpTokens[sender] -= lpTokens;

        _hski.setTaxExclusion(SWAP_ROUTER, true);

        (uint256 hskiReceived, uint256 bnbReceived) = uniswapV2Router.removeLiquidityETH
        (
            address(this),  //Token address
            lpTokens,       //LP tokens to remove.
            minHski,        //Minimum HSKI
            minBnb,         //Minimum BNB
            sender,         //Recipient of tokens
            block.timestamp //Deadline
        );

        _hski.setTaxExclusion(SWAP_ROUTER, false);

        return (hskiReceived, bnbReceived);
    }

    //Lock contract BNB in the HSKI LP
    function lockLiquidity() external
    {
        //Use all BNB in contract address
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);
        uint256 bnbAmount = contractBalance / 2;

        uint256 startingHskiAmount = _hski.balanceOf(_swapReceiver);

        //Swap BNB for HSKI
        swapBNBforHSKI(bnbAmount, 0, _swapReceiver);

        uint256 hskiAmount = _hski.balanceOf(_swapReceiver) - startingHskiAmount;

        //Uniswap factory doesn't allow reciever to be token contract address
        _hski.transfer(_swapReceiver, address(this), hskiAmount);

        //Add liquidity to uniswap
        (uint256 hskiAdded, uint256 bnbAdded, uint256 lpReceived) = _addLiquidity(hskiAmount, bnbAmount, 0, 0, address(this));

        _hskiLocked += hskiAdded;
        _bnbLocked += bnbAdded;

        emit LiquidityLocked(address(this), hskiAdded, bnbAdded, lpReceived);
    }
}