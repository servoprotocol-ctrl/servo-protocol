// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";
import {IPoolManagerMinimal, IUnlockCallback, PoolKey, SwapParams} from "./interfaces/IPoolManagerMinimal.sol";

/// @title UniswapV4SwapAdapter
/// @notice Production ISwapAdapter for Servo, swapping USDG into stock tokens through
///         Uniswap v4 on Robinhood Chain. Stock-token liquidity on the chain lives in
///         v4 PoolManager pools (the v3 stock pools are empty), so this adapter speaks
///         to the PoolManager directly via the standard unlock-callback pattern rather
///         than the chain's modified Universal Router fork, keeping the integration on
///         the canonical, unmodified core contract.
///
///         The owner pins a PoolKey per output token (e.g. the USDG/NVDA 0.30% pool,
///         hooks 0x0), so routing is explicit and auditable. `minOut` is enforced on the
///         amount actually taken for the recipient.
contract UniswapV4SwapAdapter is ISwapAdapter, IUnlockCallback, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // v4-core TickMath bounds (price limits for a full-range swap).
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    IPoolManagerMinimal public immutable POOL_MANAGER;

    /// @notice Pool used to reach each output token. tickSpacing == 0 means unset.
    mapping(address tokenOut => PoolKey key) public poolFor;

    event PoolSet(address indexed tokenOut, address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks);
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address to);

    error NoPool(address tokenOut);
    error TokenNotInPool(address tokenIn, address tokenOut);
    error NotPoolManager(address caller);
    error InsufficientOutput(uint256 amountOut, uint256 minOut);
    error ZeroAddress();
    error ZeroAmount();

    constructor(IPoolManagerMinimal poolManager, address initialOwner) Ownable(initialOwner) {
        if (address(poolManager) == address(0)) revert ZeroAddress();
        POOL_MANAGER = poolManager;
    }

    /// @notice Pin the v4 pool used to reach `tokenOut`. The key must contain `tokenOut`
    ///         as one of its currencies; set tickSpacing 0 to clear.
    function setPool(address tokenOut, PoolKey calldata key) external onlyOwner {
        if (tokenOut == address(0)) revert ZeroAddress();
        if (key.tickSpacing != 0 && key.currency0 != tokenOut && key.currency1 != tokenOut) {
            revert TokenNotInPool(address(0), tokenOut);
        }
        poolFor[tokenOut] = key;
        emit PoolSet(tokenOut, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc ISwapAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        PoolKey memory key = poolFor[tokenOut];
        if (key.tickSpacing == 0) revert NoPool(tokenOut);

        bool zeroForOne;
        if (tokenIn == key.currency0 && tokenOut == key.currency1) zeroForOne = true;
        else if (tokenIn == key.currency1 && tokenOut == key.currency0) zeroForOne = false;
        else revert TokenNotInPool(tokenIn, tokenOut);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        bytes memory result = POOL_MANAGER.unlock(abi.encode(key, tokenIn, tokenOut, amountIn, zeroForOne, to));
        amountOut = abi.decode(result, (uint256));
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);

        emit Swapped(tokenIn, tokenOut, amountIn, amountOut, to);
    }

    /// @notice PoolManager re-enters here inside `unlock`: perform the swap, pay the
    ///         input currency, and take the output straight to the recipient.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager(msg.sender);
        (PoolKey memory key, address tokenIn, address tokenOut, uint256 amountIn, bool zeroForOne, address to) =
            abi.decode(data, (PoolKey, address, address, uint256, bool, address));

        int256 delta = POOL_MANAGER.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn), // negative = exact input
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1
            }),
            ""
        );

        // BalanceDelta packs amount0 in the upper 128 bits, amount1 in the lower;
        // positive amounts are owed to us, negative are owed to the pool.
        int128 amount0 = int128(delta >> 128);
        int128 amount1 = int128(delta);
        uint256 owed = uint256(uint128(zeroForOne ? -amount0 : -amount1));
        uint256 received = uint256(uint128(zeroForOne ? amount1 : amount0));

        // Pay the input: sync, transfer, settle.
        POOL_MANAGER.sync(tokenIn);
        IERC20(tokenIn).safeTransfer(address(POOL_MANAGER), owed);
        POOL_MANAGER.settle();

        // Deliver the output directly to the recipient.
        POOL_MANAGER.take(tokenOut, to, received);

        return abi.encode(received);
    }

    /// @notice Recover tokens stranded in the adapter (it should hold none between swaps).
    function rescue(address token, address recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }
}
