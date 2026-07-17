// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";

/// @notice Minimal Uniswap v3 SwapRouter02 surface (no deadline in params).
interface IV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

/// @title UniswapV3SwapAdapter
/// @notice Production ISwapAdapter for Servo, routing USDG -> stock-token swaps through
///         Uniswap v3 (the primary public AMM on Robinhood Chain). The owner configures
///         a v3 path per output token, so a swap can be single-hop (USDG/stock) or
///         multi-hop (USDG/WETH/stock) without any code change. The caller's `minOut`
///         is enforced by the router as `amountOutMinimum`, so slippage is bounded.
///
///         Deployment notes for Robinhood Chain:
///           - Pass the VERIFIED SwapRouter02 address (chain 4663) to the constructor.
///             The chain's Universal Router is a modified fork and has look-alike
///             decoys; the standard SwapRouter02 ABI used here avoids that surface.
///           - Paths are v3-encoded: tokenIn(20) | fee(3) | tokenOut(20) [ | fee | ... ].
contract UniswapV3SwapAdapter is ISwapAdapter, Ownable {
    using SafeERC20 for IERC20;

    IV3SwapRouter public immutable ROUTER;

    /// @notice Encoded v3 path used to reach each output token (from USDG).
    mapping(address tokenOut => bytes path) public pathFor;

    event PathSet(address indexed tokenOut, bytes path);
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address to);

    error NoPath(address tokenOut);
    error ZeroAddress();
    error ZeroAmount();

    constructor(IV3SwapRouter router, address initialOwner) Ownable(initialOwner) {
        if (address(router) == address(0)) revert ZeroAddress();
        ROUTER = router;
    }

    /// @notice Set (or clear) the v3 path for an output token. The path must start at the
    ///         intended input token (USDG) and end at `tokenOut`.
    function setPath(address tokenOut, bytes calldata path) external onlyOwner {
        if (tokenOut == address(0)) revert ZeroAddress();
        pathFor[tokenOut] = path;
        emit PathSet(tokenOut, path);
    }

    /// @inheritdoc ISwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        bytes memory path = pathFor[tokenOut];
        if (path.length == 0) revert NoPath(tokenOut);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);

        amountOut = ROUTER.exactInput(
            IV3SwapRouter.ExactInputParams({path: path, recipient: to, amountIn: amountIn, amountOutMinimum: minOut})
        );

        IERC20(tokenIn).forceApprove(address(ROUTER), 0);
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut, to);
    }
}
