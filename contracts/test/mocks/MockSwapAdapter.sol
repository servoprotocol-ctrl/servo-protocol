// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapAdapter} from "../../src/interfaces/ISwapAdapter.sol";
import {MockToken} from "./MockToken.sol";

/// @notice Test swap venue: pulls `tokenIn` from the caller and mints `stock` to `to`
///         at a fixed rate (stockOut = amountIn * rateNum / rateDen). Stands in for a
///         real DEX router adapter on Robinhood Chain.
contract MockSwapAdapter is ISwapAdapter {
    MockToken public immutable STOCK;
    uint256 public immutable rateNum;
    uint256 public immutable rateDen;

    error UnexpectedTokenOut();
    error Slippage();

    constructor(MockToken stock_, uint256 rateNum_, uint256 rateDen_) {
        STOCK = stock_;
        rateNum = rateNum_;
        rateDen = rateDen_;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        returns (uint256 amountOut)
    {
        if (tokenOut != address(STOCK)) revert UnexpectedTokenOut();
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = (amountIn * rateNum) / rateDen;
        if (amountOut < minOut) revert Slippage();
        STOCK.mint(to, amountOut);
    }
}
