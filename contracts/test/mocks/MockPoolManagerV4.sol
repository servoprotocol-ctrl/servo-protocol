// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUnlockCallback, PoolKey, SwapParams} from "../../src/interfaces/IPoolManagerMinimal.sol";
import {MockToken} from "./MockToken.sol";

/// @notice Test stand-in for the Uniswap v4 PoolManager. Reproduces the unlock ->
///         callback -> swap/sync/settle/take flow with BalanceDelta packing, converting
///         at a fixed rate and minting the output token on take. Enforces that the input
///         is actually paid before settle, like the real singleton.
contract MockPoolManagerV4 {
    uint256 public immutable rateNum;
    uint256 public immutable rateDen;

    bool internal unlocked;
    address internal syncedCurrency;
    uint256 internal syncedBalance;
    uint256 internal owedIn;

    error NotUnlocked();
    error Underpaid();

    constructor(uint256 rateNum_, uint256 rateDen_) {
        rateNum = rateNum_;
        rateDen = rateDen_;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function swap(PoolKey memory, SwapParams memory p, bytes calldata) external view returns (int256 delta) {
        if (!unlocked) revert NotUnlocked();
        require(p.amountSpecified < 0, "exactIn only");
        uint256 amountIn = uint256(-p.amountSpecified);
        uint256 amountOut = (amountIn * rateNum) / rateDen;

        int128 a0;
        int128 a1;
        if (p.zeroForOne) {
            a0 = -int128(int256(amountIn));
            a1 = int128(int256(amountOut));
        } else {
            a1 = -int128(int256(amountIn));
            a0 = int128(int256(amountOut));
        }
        delta = int256((uint256(uint128(a0)) << 128) | uint256(uint128(a1)));
    }

    function sync(address currency) external {
        if (!unlocked) revert NotUnlocked();
        syncedCurrency = currency;
        syncedBalance = IERC20(currency).balanceOf(address(this));
        // The adapter owes whatever it is about to transfer; recorded for settle check.
    }

    function settle() external payable returns (uint256 paid) {
        if (!unlocked) revert NotUnlocked();
        paid = IERC20(syncedCurrency).balanceOf(address(this)) - syncedBalance;
        if (paid == 0) revert Underpaid();
    }

    function take(address currency, address to, uint256 amount) external {
        if (!unlocked) revert NotUnlocked();
        MockToken(currency).mint(to, amount);
    }
}
