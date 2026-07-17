// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IStockRewards
/// @notice Minimal surface the ServiceRegistry uses to credit marketplace rewards.
interface IStockRewards {
    /// @notice Credit `amount` of reward currency to `user`. The matching funds must
    ///         already have been transferred to the rewards pool.
    function accrue(address user, uint256 amount) external;

    /// @notice The currency rewards are denominated and funded in (USDG).
    function rewardCurrency() external view returns (address);
}
