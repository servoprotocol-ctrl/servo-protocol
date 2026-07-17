// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ISwapAdapter
/// @notice Swaps one ERC-20 into another through some venue (a DEX router on
///         Robinhood Chain). Kept behind an interface so the swap venue can change,
///         or be mocked in tests, without touching the contracts that use it.
interface ISwapAdapter {
    /// @notice Swap `amountIn` of `tokenIn` into `tokenOut`, delivering the output to `to`.
    /// @dev    The caller must have approved this adapter to pull `amountIn` of `tokenIn`.
    ///         Must deliver at least `minOut` of `tokenOut` to `to` or revert.
    /// @return amountOut The amount of `tokenOut` delivered.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        returns (uint256 amountOut);
}
