// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "./MockToken.sol";

/// @notice Test stand-in for Uniswap v3 SwapRouter02. Decodes the first and last tokens
///         from the v3 path, pulls `amountIn` of the input token from the caller, and
///         mints the output token to `recipient` at a fixed rate. Exercises the adapter's
///         path encoding, approval, and minOut plumbing without a live Uniswap.
contract MockV3Router {
    uint256 public immutable rateNum;
    uint256 public immutable rateDen;

    error Slippage();

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    constructor(uint256 rateNum_, uint256 rateDen_) {
        rateNum = rateNum_;
        rateDen = rateDen_;
    }

    function exactInput(ExactInputParams calldata p) external returns (uint256 amountOut) {
        address tokenIn = address(bytes20(p.path[0:20]));
        address tokenOut = address(bytes20(p.path[p.path.length - 20:p.path.length]));

        IERC20(tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        amountOut = (p.amountIn * rateNum) / rateDen;
        if (amountOut < p.amountOutMinimum) revert Slippage();
        MockToken(tokenOut).mint(p.recipient, amountOut);
    }
}
