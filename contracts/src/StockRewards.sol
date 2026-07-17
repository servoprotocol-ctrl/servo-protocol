// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";
import {IStockRewards} from "./interfaces/IStockRewards.sol";

/// @title StockRewards
/// @notice Dividend rewards for using the Servo marketplace: earn stocks for using the
///         network. A configurable slice of the protocol fee on every settled trade is
///         routed here and credited to the participant who made the trade. Rewards
///         accrue in USDG and are claimed as tokenized stocks (Robinhood Stock Tokens),
///         so using the machine economy pays you back in real equities.
///
///         Design notes:
///           - Accrual is O(1) and pull-based. The ServiceRegistry credits a user on
///             each purchase; users claim whenever they like. No loops, no staking.
///           - Solvent by construction: the USDG backing a reward is transferred into
///             this pool at accrual time, so `reserves()` always covers `totalOwed`.
///           - The USDG -> stock swap runs through a pluggable ISwapAdapter, keeping the
///             choice of DEX venue out of this contract. Users pass a `minOut` slippage
///             bound, and can always fall back to claiming plain USDG.
contract StockRewards is IStockRewards, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------- storage

    /// @notice The currency rewards are funded and denominated in (USDG).
    IERC20 public immutable REWARD_CURRENCY;

    /// @notice Accounts allowed to credit rewards (the ServiceRegistry).
    mapping(address recorder => bool) public isRecorder;

    /// @notice Swap venue used to convert USDG rewards into a stock token.
    ISwapAdapter public swapAdapter;

    /// @notice Curated set of stock tokens a user may claim into.
    mapping(address stock => bool) public isAllowedStock;

    /// @notice Optional default stock token, so users can claim in one click.
    address public defaultStock;

    /// @notice USDG rewards owed to each participant.
    mapping(address user => uint256) public accrued;

    /// @notice Outstanding reward liabilities (the sum of `accrued`).
    uint256 public totalOwed;
    /// @notice Lifetime rewards credited.
    uint256 public totalEarned;
    /// @notice Lifetime rewards claimed, in USDG terms.
    uint256 public totalClaimed;

    // --------------------------------------------------------------- events

    event Accrued(address indexed user, uint256 amount, uint256 totalOwed);
    event ClaimedAsStock(address indexed user, address indexed stock, uint256 usdgIn, uint256 stockOut);
    event ClaimedAsUsdg(address indexed user, uint256 amount);
    event Funded(address indexed from, uint256 amount);
    event RecorderSet(address indexed recorder, bool allowed);
    event SwapAdapterSet(address indexed adapter);
    event AllowedStockSet(address indexed stock, bool allowed);
    event DefaultStockSet(address indexed stock);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    // --------------------------------------------------------------- errors

    error NotRecorder(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error NothingToClaim();
    error StockNotAllowed(address stock);
    error NoSwapAdapter();
    error NoDefaultStock();
    error AmountExceedsFree();

    // ---------------------------------------------------------- constructor

    constructor(IERC20 rewardCurrency_, address initialOwner) Ownable(initialOwner) {
        if (address(rewardCurrency_) == address(0)) revert ZeroAddress();
        REWARD_CURRENCY = rewardCurrency_;
    }

    modifier onlyRecorder() {
        if (!isRecorder[msg.sender]) revert NotRecorder(msg.sender);
        _;
    }

    // ------------------------------------------------------------- accrual

    /// @inheritdoc IStockRewards
    function rewardCurrency() external view returns (address) {
        return address(REWARD_CURRENCY);
    }

    /// @notice Credit `amount` of USDG rewards to `user`. Called by the ServiceRegistry
    ///         on each settled purchase; the matching USDG is transferred into this pool
    ///         first, so the accounting stays solvent.
    function accrue(address user, uint256 amount) external onlyRecorder {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        accrued[user] += amount;
        totalOwed += amount;
        totalEarned += amount;
        emit Accrued(user, amount, totalOwed);
    }

    /// @notice Top up the reward pool directly (e.g. from the treasury).
    function fund(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        REWARD_CURRENCY.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount);
    }

    // --------------------------------------------------------------- claim

    /// @notice Claim your accrued rewards as `stock`, swapped from USDG via the adapter.
    /// @param stock  A curated stock token to receive.
    /// @param minOut Minimum amount of `stock` to accept (slippage bound).
    function claimAsStock(address stock, uint256 minOut) external nonReentrant returns (uint256) {
        return _claimAsStock(msg.sender, stock, minOut);
    }

    /// @notice Claim into the protocol's default stock token in one call.
    function claimDefault(uint256 minOut) external nonReentrant returns (uint256) {
        address stock = defaultStock;
        if (stock == address(0)) revert NoDefaultStock();
        return _claimAsStock(msg.sender, stock, minOut);
    }

    /// @notice Fallback: claim your accrued rewards as plain USDG instead of a stock.
    function claimAsUsdg() external nonReentrant returns (uint256 amount) {
        amount = accrued[msg.sender];
        if (amount == 0) revert NothingToClaim();
        accrued[msg.sender] = 0;
        totalOwed -= amount;
        totalClaimed += amount;
        REWARD_CURRENCY.safeTransfer(msg.sender, amount);
        emit ClaimedAsUsdg(msg.sender, amount);
    }

    function _claimAsStock(address user, address stock, uint256 minOut) internal returns (uint256 stockOut) {
        if (!isAllowedStock[stock]) revert StockNotAllowed(stock);
        ISwapAdapter adapter = swapAdapter;
        if (address(adapter) == address(0)) revert NoSwapAdapter();

        uint256 amount = accrued[user];
        if (amount == 0) revert NothingToClaim();

        // effects before interactions
        accrued[user] = 0;
        totalOwed -= amount;
        totalClaimed += amount;

        // swap USDG -> stock, delivered straight to the user
        REWARD_CURRENCY.forceApprove(address(adapter), amount);
        stockOut = adapter.swap(address(REWARD_CURRENCY), stock, amount, minOut, user);
        REWARD_CURRENCY.forceApprove(address(adapter), 0);

        emit ClaimedAsStock(user, stock, amount, stockOut);
    }

    // ---------------------------------------------------------------- admin

    function setRecorder(address recorder, bool allowed) external onlyOwner {
        if (recorder == address(0)) revert ZeroAddress();
        isRecorder[recorder] = allowed;
        emit RecorderSet(recorder, allowed);
    }

    function setSwapAdapter(address adapter) external onlyOwner {
        swapAdapter = ISwapAdapter(adapter);
        emit SwapAdapterSet(adapter);
    }

    function setAllowedStock(address stock, bool allowed) external onlyOwner {
        if (stock == address(0)) revert ZeroAddress();
        isAllowedStock[stock] = allowed;
        emit AllowedStockSet(stock, allowed);
    }

    function setDefaultStock(address stock) external onlyOwner {
        if (stock != address(0) && !isAllowedStock[stock]) revert StockNotAllowed(stock);
        defaultStock = stock;
        emit DefaultStockSet(stock);
    }

    /// @notice Recover tokens sent here by mistake. For the reward currency, only the
    ///         balance in excess of outstanding liabilities (`totalOwed`) can be moved,
    ///         so users' accrued rewards can never be swept.
    function rescue(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (token == address(REWARD_CURRENCY)) {
            uint256 free = REWARD_CURRENCY.balanceOf(address(this)) - totalOwed;
            if (amount > free) revert AmountExceedsFree();
        }
        IERC20(token).safeTransfer(to, amount);
        emit Rescued(token, to, amount);
    }

    // ----------------------------------------------------------------- views

    /// @notice USDG currently held to back rewards. Always >= `totalOwed`.
    function reserves() external view returns (uint256) {
        return REWARD_CURRENCY.balanceOf(address(this));
    }

    /// @notice Rewards `user` can currently claim, in USDG terms.
    function claimable(address user) external view returns (uint256) {
        return accrued[user];
    }
}
