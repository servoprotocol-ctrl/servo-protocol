// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Minimal Uniswap v4 core surface used by Servo's v4 swap adapter.
///         Currency and IHooks are plain addresses here; the ABI encoding is identical
///         to v4-core's type wrappers, so calls line up with the deployed PoolManager.

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified; // negative = exact input
    uint160 sqrtPriceLimitX96;
}

interface IPoolManagerMinimal {
    function unlock(bytes calldata data) external returns (bytes memory);

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);

    function sync(address currency) external;

    function settle() external payable returns (uint256 paid);

    function take(address currency, address to, uint256 amount) external;
}

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}
