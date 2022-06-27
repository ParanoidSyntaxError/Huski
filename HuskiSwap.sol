// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./Huski.sol";
import "./IERC20.sol";

contract HuskiSwap
{
    event LiquidityLocked(address indexed from, uint256 hskiValue, uint256 bnbValue, uint256 lpValue);

    //TESTNET: https://pancake.kiemtienonline360.com/#/swap
    address private constant SWAP_ROUTER = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3; 

    mapping (address => uint256) private _lpCredits;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    Huski internal _hski;

    constructor(Huski huskiContract)
    {
        _hski = huskiContract;

        //Uniswap initialization
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(SWAP_ROUTER);
        uniswapV2Pair = IUniswapV2Factory(swapRouter.factory()).createPair(address(this), swapRouter.WETH());
        uniswapV2Router = swapRouter;
    }

    // Recieve BNB from Pancakeswap router when swaping
    receive() external payable { } 

    function lpTokenBalanceOf(address account) external view returns (uint256)
    {
        return _lpCredits[account];
    }

    //Tax free swap BNB for HSKI
    function buyHSKIforBNB(uint256 minHski) external payable returns (bool)
    {
        require(msg.value > 0);

        _hski.setTaxExclusion(uniswapV2Pair, true);

        _swapBNBforToken(msg.value, minHski, address(this), msg.sender);
    
        _hski.setTaxExclusion(uniswapV2Pair, false);

        return true;
    }

    //Tax free swap token for HSKI
    function buyHSKIforToken(uint256 tokenAmount, uint256 minHski, address tokenContract) external returns (bool)
    {
        require(tokenAmount > 0);

        IERC20(tokenContract).transfer(address(this), tokenAmount);

        _hski.setTaxExclusion(uniswapV2Pair, true);

        _swapTokenforToken(tokenAmount, minHski, tokenContract, address(this), msg.sender);
    
        _hski.setTaxExclusion(uniswapV2Pair, false);
        
        return true;
    }

    //Tax free liquidity providing
    function addLiquidityBNB(uint256 hskiAmount, uint256 minHski, uint256 minBnb) external payable returns (uint256, uint256, uint256)
    {
        //Transfer HSKI to contract
        _hski.taxFreeTransfer(msg.sender, address(this), hskiAmount);

        //Add liquidity from contract
        (uint256 hskiSent, uint256 bnbSent, uint256 lpTokens) = _addLiquidityBNB(hskiAmount, msg.value, minHski, minBnb, address(this));

        //Return unused HSKI
        _hski.taxFreeTransfer(address(this), msg.sender, hskiAmount - hskiSent);

        //Credit LP tokens
        _lpCredits[msg.sender] += lpTokens;

        //Return unused BNB
        (bool sent,) = msg.sender.call{value: msg.value - bnbSent}("");
        require(sent == true);

        return (hskiSent, bnbSent, lpTokens);
    }

    function addLiquidityToken(uint256 hskiAmount, uint256 tokenAmount, uint256 minHski, uint256 minToken, address tokenContract) external returns(uint256, uint256, uint256)
    {
        //Transfer HSKI to contract
        _hski.taxFreeTransfer(msg.sender, address(this), hskiAmount);

        //Add liquidity from contract
        (uint256 hskiSent, uint256 tokensSent, uint256 lpTokens) = _addLiquidityToken(hskiAmount, tokenAmount, minHski, minToken, tokenContract, address(this));

        //Return unused HSKI
        _hski.taxFreeTransfer(address(this), msg.sender, hskiAmount - hskiSent);

        //Credit LP tokens
        _lpCredits[msg.sender] += lpTokens;

        //Return unused tokens
        uint256 remainingTokens = tokenAmount - tokensSent;

        if(remainingTokens > 0) 
        {
            IERC20(tokenContract).transfer(msg.sender, remainingTokens);
        }
        
        return (hskiSent, tokensSent, lpTokens);
    }

    //Tax free liquidity removal
    function removeLiquidityBNB(uint256 lpTokens, uint256 minHski, uint256 minBnb) external returns (uint256, uint256)
    {
        _lpCredits[msg.sender] -= lpTokens;

        _hski.setTaxExclusion(SWAP_ROUTER, true);

        (uint256 hskiReceived, uint256 bnbReceived) = _removeLiquidityBNB(lpTokens, minHski, minBnb, msg.sender);

        _hski.setTaxExclusion(SWAP_ROUTER, false);

        return (hskiReceived, bnbReceived);
    }

    function removeLiquidityToken() external returns (uint256, uint256)
    {
        
    }

    //Buy and burn HSKI with contracts BNB
    function liquidityBurn() public
    {
        require(address(this).balance > 0);

        uint256 startingHskiAmount = _hski.balanceOf(_hski.huskiPool());

        //Swap BNB for HSKI
        _swapBNBforToken(address(this).balance, 0, address(this), _hski.huskiPool());

        uint256 hskiAmount = _hski.balanceOf(_hski.huskiPool()) - startingHskiAmount;

        //Uniswap factory doesn't allow reciever to be token contract address
        _hski.taxFreeTransfer(_hski.huskiPool(), address(this), hskiAmount);

        _hski.contractBurn();
    }

    function _swapBNBforToken(uint256 bnbAmount, uint256 minToken, address tokenContract, address receiver) internal returns (uint256[] memory)
    {
        address[] memory swapPath;
        swapPath[0] = uniswapV2Router.WETH();
        swapPath[1] = tokenContract;

        return uniswapV2Router.swapExactETHForTokens{ value : bnbAmount } //BNB value
        (
            minToken,       //Minimum HSKI
            swapPath,       //Routing path
            receiver,       //Receiver (can't set reciever to token address)
            block.timestamp //Deadline
        );
    }

    function _swapTokenforToken(uint256 tokenInAmount, uint256 minTokenOut, address tokenIn, address tokenOut, address receiver) internal returns (uint256[] memory)
    {
        address[] memory swapPath;
        swapPath[0] = tokenIn;
        swapPath[1] = tokenOut;

        return uniswapV2Router.swapExactTokensForTokens
        (
            tokenInAmount,  //Exact token in
            minTokenOut,    //Minimum token out
            swapPath,       //Routing path
            receiver,       //Receiver (can't set reciever to token address)
            block.timestamp //Deadline
        );
    }

    function _addLiquidityBNB(uint256 hskiAmount, uint256 bnbAmount, uint256 minHski, uint256 minBnb, address lpReceiver) private returns (uint256, uint256, uint256)
    {
        require(bnbAmount > 0);
        require(hskiAmount > 0);

        //Approve token transfer to cover all possible scenarios
        _hski.approve(address(uniswapV2Router), hskiAmount);

        //Add liquidity to BNB/HSKI pool
        return uniswapV2Router.addLiquidityETH{ value : bnbAmount } //BNB value
        (
            address(this),  //HSKI contract
            hskiAmount,     //HSKI amount
            minHski,        //Minimum HSKI
            minBnb,         //Minimum BNB
            lpReceiver,     //LP token receiver
            block.timestamp //Deadline
        );
    }

    function _addLiquidityToken(uint256 hskiAmount, uint256 tokenAmount, uint256 minHski, uint256 minToken, address tokenContract, address lpReceiver) private returns (uint256, uint256, uint256)
    {
        require(tokenAmount > 0);
        require(hskiAmount > 0);

        //Approve token transfer to cover all possible scenarios
        _hski.approve(address(uniswapV2Router), hskiAmount);
        IERC20(tokenContract).approve(address(uniswapV2Router), tokenAmount);

        return uniswapV2Router.addLiquidity
        (
            address(this),  //HSKI contract
            tokenContract,  //Token contract
            hskiAmount,     //HSKI amount
            tokenAmount,    //Token amount
            minHski,        //Minimum HSKI
            minToken,       //Minimum token
            lpReceiver,     //LP token receiver
            block.timestamp //Deadline
        );
    }

    function _removeLiquidityBNB(uint256 lpAmount, uint256 minHski, uint256 minBnb, address receiver) private returns (uint256, uint256)
    {
        require(lpAmount > 0);

        return uniswapV2Router.removeLiquidityETH
        (
            address(this),  //HSKI contract
            lpAmount,       //LP tokens to remove
            minHski,        //Minimum HSKI
            minBnb,         //Minimum BNB
            receiver,       //Recipient of tokens
            block.timestamp //Deadline
        );
    }

    function _removeLiquidityToken(uint256 lpAmount, uint256 minHski, uint256 minToken, address tokenContract, address receiver) private returns (uint256, uint256)
    {
        require(lpAmount > 0);

        return uniswapV2Router.removeLiquidity
        (
            address(this),  //HSKI contract
            tokenContract,  //Token contract
            lpAmount,       //LP tokens to remove
            minHski,        //Minimum HSKI
            minToken,       //Minimum token
            receiver,       //Recipient of tokens
            block.timestamp //Deadline
        );
    }
}