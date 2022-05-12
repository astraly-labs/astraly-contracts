%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero, assert_le
from starkware.cairo.common.uint256 import Uint256, uint256_check, uint256_lt, uint256_sub
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_block_timestamp,
    get_contract_address,
)

from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_le,
    uint256_checked_sub_lt,
    uint256_checked_div_rem,
    uint256_checked_mul,
)

from contracts.utils import get_array, uint256_is_zero
from contracts.erc4626.ERC4626 import asset

@contract_interface
namespace IStrategy:
    func redeemUnderlying(amount : Uint256) -> (res : Uint256):
    end
    func balanceOfUnderlying(user : felt) -> (res : Uint256):
    end
    func underlying() -> (address : felt):
    end
    func mint(amount : Uint256) -> (res : Uint256):
    end
end

# # @notice Data for a given strategy.
# # @param trusted Whether the strategy is trusted.
# # @param balance The amount of underlying tokens held in the strategy.
struct StrategyData:
    member trusted : felt  # 0 (false) or 1 (true)
    member balance : Uint256
end

####################################################################################
#                                   Events
####################################################################################
@event
func FeePercentUpdated(user : felt, new_fee_percent : felt):
end

@event
func HarvestWindowUpdated(user : felt, new_harvest_window : felt):
end

# @notice Emitted when the harvest delay is updated.
# @param user The authorized user who triggered the update.
# @param new_harvest_delay The new harvest delay.
@event
func HarvestDelayUpdated(user : felt, new_harvest_delay : felt):
end

# @notice Emitted when the harvest delay is scheduled to be updated next harvest.
# @param user The authorized user who triggered the update.
# @param new_harvest_delay The scheduled updated harvest delay.
@event
func HarvestDelayUpdateScheduled(user : felt, new_harvest_delay : felt):
end

# @notice Emitted when the target float percentage is updated.
# @param user The authorized user who triggered the update.
# @param new_target_float_percent The new target float percentage.
@event
func TargetFloatPercentUpdated(user : felt, new_target_float_percent : felt):
end

@event
func Harvest(user : felt, strategies_len : felt, strategies : felt*):
end

# @notice Emitted after the Vault deposits into a strategy contract.
# @param user The authorized user who triggered the deposit.
# @param strategy The strategy that was deposited into.
# @param underlyingAmount The amount of underlying tokens that were deposited.
@event
func StrategyDeposit(user : felt, strategy_address : felt, underlying_amount : Uint256):
end

# @notice Emitted after the Vault withdraws funds from a strategy contract.
# @param user The authorized user who triggered the withdrawal.
# @param strategy The strategy that was withdrawn from.
# @param underlyingAmount The amount of underlying tokens that were withdrawn.
@event
func StrategyWithdrawal(user : felt, strategy_address : felt, underlying_amount : Uint256):
end

@event
func StrategyTrusted(user : felt, strategy_address : felt):
end

@event
func StrategyDistrusted(user : felt, strategy_address : felt):
end

@event
func FeesClaimed(user : felt, amount : Uint256):
end

####################################################################################
#                               Storage Variables
####################################################################################

@storage_var
func base_unit() -> (unit : felt):
end

@storage_var
func fee_percent() -> (fee : felt):
end

@storage_var
func harvest_window() -> (window : felt):
end

@storage_var
func harvest_delay() -> (delay : felt):
end

@storage_var
func next_harvest_delay() -> (delay : felt):
end

# # @notice The desired float percentage of holdings.
# # @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
@storage_var
func target_float_percent() -> (percent : felt):
end

# # @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
# # @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
@storage_var
func total_strategy_holdings() -> (holdings : Uint256):
end

# # @notice Maps strategies to data the Vault holds on them.
@storage_var
func strategy_data(strategy : felt) -> (data : StrategyData):
end

# # @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
# # @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
@storage_var
func last_harvest_window_start() -> (start : felt):
end

# # @notice A timestamp representing when the most recent harvest occurred.
@storage_var
func last_harvest() -> (harvest : felt):
end

# # @notice The amount of locked profit at the end of the last harvest.
@storage_var
func max_locked_profit() -> (profit : Uint256):
end

# # @notice An ordered array of strategies representing the withdrawal queue.
# # @dev The queue is processed in descending order.
# # @dev Returns a tupled-array of (array_len, Strategy[])
@storage_var
func withdrawal_queue(index : felt) -> (strategy_address : felt):
end

@storage_var
func withdrawal_queue_length() -> (length : felt):
end

####################################################################################
#                                  View Functions
####################################################################################
# # @notice Gets the full withdrawal queue.
# # @return An ordered array of strategies representing the withdrawal queue.
@view
func getWithdrawalQueue{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    queue_len : felt, queue : felt*
):
    alloc_locals
    let (length : felt) = withdrawal_queue_length.read()
    let (mapping_ref : felt) = get_label_location(withdrawal_queue.read)
    let (array : felt*) = alloc()

    get_array(length, array, mapping_ref)
    return (length, array)
end

@view
func totalFloat{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    float : Uint256
):
    let (underlying : felt) = asset()
    let (address_this : felt) = get_contract_address()
    let (balance_of_this : Uint256) = IERC20.balanceOf(underlying, address_this)

    return (balance_of_this)
end

# @notice Calculates the current amount of locked profit.
# @return The current amount of locked profit.
@view
func lockedProfit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Uint256
):
    alloc_locals
    let (previous_harvest : felt) = last_harvest.read()
    let (harvest_interval : felt) = harvest_delay.read()
    let (block_timestamp : felt) = get_block_timestamp()

    let (harvest_delay_passed : felt) = is_le(previous_harvest + harvest_interval, block_timestamp)
    # If the harvest delay has passed, there is no locked profit.
    # Cannot overflow on human timescales since harvestInterval is capped.
    if harvest_delay_passed == TRUE:
        return (Uint256(0, 0))
    end

    let (maximum_locked_profit : Uint256) = max_locked_profit.read()

    # Compute how much profit remains locked based on the last harvest and harvest delay.
    # It's impossible for the previous harvest to be in the future, so this will never underflow.
    # maximumLockedProfit - (maximumLockedProfit * (block.timestamp - previousHarvest)) / harvestInterval;
    let sub : felt = block_timestamp - previous_harvest
    let (mul : Uint256) = uint256_checked_mul(maximum_locked_profit, Uint256(sub, 0))
    let (div : Uint256, _) = uint256_checked_div_rem(mul, Uint256(harvest_interval, 0))
    let (res : Uint256) = uint256_checked_sub_le(maximum_locked_profit, div)
    return (res)
end

# @notice Calculates the total amount of underlying tokens the Vault holds.
# @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
@view
func totalHoldings{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    total_underlying_held : Uint256
):
    let (locked_profit : Uint256) = lockedProfit()
    let (current_total_strategy_holdings : Uint256) = total_strategy_holdings.read()
    let (total_underlying_held : Uint256) = uint256_checked_sub_le(
        current_total_strategy_holdings, locked_profit
    )
    let (total_float : Uint256) = totalFloat()
    let (add_float : Uint256) = uint256_checked_add(total_underlying_held, total_float)
    return (add_float)
end

@view
func totalStrategyHoldings{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    holdings : Uint256
):
    let (holdings : Uint256) = total_strategy_holdings.read()
    return (holdings)
end

@view
func feePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (res : felt) = fee_percent.read()
    return (res)
end

@view
func harvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    delay : felt
):
    let (delay : felt) = harvest_delay.read()
    return (delay)
end

@view
func harvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    window : felt
):
    let (window : felt) = harvest_window.read()
    return (window)
end

@view
func targetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    percent : felt
):
    let (percent : felt) = target_float_percent.read()
    return (percent)
end

####################################################################################
#                                  External Functions
####################################################################################
func set_fee_percent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt):
    assert_not_zero(fee)
    fee_percent.write(fee)
    let (caller : felt) = get_caller_address()
    FeePercentUpdated.emit(caller, fee)
    return ()
end

# # @notice Sets a new harvest window.
# # @param newHarvestWindow The new harvest window.
# # @dev harvest_delay must be set before calling.
func set_harvest_window{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    window : felt
):
    let (delay) = harvest_delay.read()
    assert_le(window, delay)
    harvest_window.write(window)
    let (caller : felt) = get_caller_address()
    HarvestDelayUpdated.emit(caller, window)
    return ()
end

# # @notice Sets a new harvest delay.
# # @param newHarvestDelay The new harvest delay.
func set_harvest_delay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_delay : felt
):
    alloc_locals

    let (local delay) = harvest_delay.read()
    assert_not_zero(new_delay)
    assert_le(new_delay, 31536000)  # 31,536,000 = 365 days = 1 year

    let (caller : felt) = get_caller_address()
    # If the previous delay is 0, we should set immediately
    if delay == 0:
        harvest_delay.write(new_delay)
        HarvestDelayUpdated.emit(caller, new_delay)
    else:
        next_harvest_delay.write(new_delay)
        HarvestDelayUpdateScheduled.emit(caller, new_delay)
    end
    return ()
end

# # @notice Sets a new target float percentage.
func set_target_float_percent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_float : felt
):
    alloc_locals
    target_float_percent.write(new_float)
    let (caller : felt) = get_caller_address()
    TargetFloatPercentUpdated.emit(caller, new_float)
    return ()
end

func set_base_unit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(token : felt):
    alloc_locals
    let (decimals : felt) = IERC20.decimals(token)
    let (asset_base_unit : felt) = pow(10, decimals)
    base_unit.write(asset_base_unit)
    return ()
end

##############################################################################
#                     HARVEST LOGIC
##############################################################################
# @notice Harvest a set of trusted strategies.
# @param strategies The trusted strategies to harvest.
# @dev Will always revert if called outside of an active
# harvest window or before the harvest delay has passed.
func harvest_investment{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategies_len : felt, strategies : felt*
):
    alloc_locals
    let (previous_harvest : felt) = last_harvest.read()
    let (harvest_interval : felt) = harvest_delay.read()
    let (block_timestamp : felt) = get_block_timestamp()

    let (harvest_delay_passed : felt) = is_le(previous_harvest + harvest_interval, block_timestamp)
    # If this is the first harvest after the last window:
    if harvest_delay_passed == TRUE:
        last_harvest_window_start.write(block_timestamp)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        let (current_last_harvest_window_start_value : felt) = last_harvest_window_start.read()
        let (current_harvest_window : felt) = harvest_window.read()
        with_attr error_message("BAD_HARVEST_TIME"):
            # We know this harvest is not the first in the window so we need to ensure it's within it.
            assert_le(
                block_timestamp, current_last_harvest_window_start_value + current_harvest_window
            )
        end
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    let (old_total_strategy_holdings : Uint256) = total_strategy_holdings.read()

    let (total_profit_accrued : Uint256, new_total_strategy_holdings : Uint256) = _check_strategies(
        strategies_len, strategies, 0, Uint256(0, 0), old_total_strategy_holdings
    )
    let (current_fee_percent : felt) = fee_percent.read()
    let (fees_accrued : Uint256, _) = uint256_checked_div_rem(
        total_profit_accrued, Uint256(current_fee_percent * (1 ** 18), 0)
    )

    # ## TODO: MINT xZKP

    let (current_locked_profit : Uint256) = lockedProfit()
    let (sum : Uint256) = uint256_checked_add(current_locked_profit, total_profit_accrued)
    let (new_max_locked_profit : Uint256) = uint256_sub(sum, fees_accrued)
    max_locked_profit.write(new_max_locked_profit)

    total_strategy_holdings.write(new_total_strategy_holdings)
    last_harvest.write(block_timestamp)
    let (caller : felt) = get_caller_address()

    let (new_harvest_delay : felt) = next_harvest_delay.read()
    if new_harvest_delay != 0:
        harvest_delay.write(new_harvest_delay)
        next_harvest_delay.write(0)
        HarvestDelayUpdated.emit(caller, new_harvest_delay)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    Harvest.emit(caller, strategies_len, strategies)
    return ()
end

func _check_strategies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategies_len : felt,
    strategies : felt*,
    index,
    total_profit_accrued : Uint256,
    total_strategy_holdings : Uint256,
) -> (total_profit_accrued : Uint256, total_strategy_holdings : Uint256):
    alloc_locals
    if index == strategies_len:
        return (total_profit_accrued, total_strategy_holdings)
    end
    Only_trusted_strategy(strategies[index])
    let (current_strategy_data : StrategyData) = strategy_data.read(strategies[index])
    let (underlying_asset : felt) = asset()
    let balance_last_harvest : Uint256 = current_strategy_data.balance
    let (balance_this_harvest : Uint256) = IERC20.balanceOf(underlying_asset, strategies[index])

    strategy_data.write(strategies[index], StrategyData(TRUE, balance_this_harvest))

    let (is_last_harvest_balance_lt : felt) = uint256_lt(balance_last_harvest, balance_this_harvest)

    let (sum : Uint256) = uint256_checked_add(total_strategy_holdings, balance_this_harvest)
    let (new_total_strategy_holdings : Uint256) = uint256_checked_sub_le(sum, balance_last_harvest)
    if is_last_harvest_balance_lt == TRUE:
        let (profit : Uint256) = uint256_checked_sub_lt(balance_this_harvest, balance_last_harvest)
        let (new_total_profit_accrued : Uint256) = uint256_checked_add(total_profit_accrued, profit)
        return _check_strategies(
            strategies_len,
            strategies,
            index + 1,
            new_total_profit_accrued,
            new_total_strategy_holdings,
        )
    else:
        return _check_strategies(
            strategies_len, strategies, index + 1, total_profit_accrued, new_total_strategy_holdings
        )
    end
end

##############################################################################
#                     STRATEGY DEPOSIT/WITHDRAWAL LOGIC
##############################################################################
func deposit_into_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt, underlying_amount : Uint256
):
    alloc_locals
    Only_trusted_strategy(strategy_address)

    let (current_total_strategy_holdings : Uint256) = total_strategy_holdings.read()
    let (new_total_strategy_holdings : Uint256) = uint256_checked_add(
        current_total_strategy_holdings, underlying_amount
    )
    total_strategy_holdings.write(new_total_strategy_holdings)
    strategy_data.write(strategy_address, StrategyData(TRUE, new_total_strategy_holdings))

    let (underlying_asset : felt) = asset()
    IERC20.approve(underlying_asset, strategy_address, underlying_amount)

    let (minted : Uint256) = IStrategy.mint(strategy_address, underlying_amount)
    with_attr error_message("MINT_FAILED"):
        let (minted_zero_tokens : felt) = uint256_is_zero(minted)
        assert minted_zero_tokens = FALSE
    end
    let (caller : felt) = get_caller_address()
    StrategyDeposit.emit(caller, strategy_address, underlying_amount)
    return ()
end

func withdraw_from_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt, underlying_amount : Uint256
):
    alloc_locals
    Only_trusted_strategy(strategy_address)
    let (current_strategy_data : StrategyData) = strategy_data.read(strategy_address)
    let (new_strategy_balance : Uint256) = uint256_checked_sub_le(
        current_strategy_data.balance, underlying_amount
    )
    strategy_data.write(strategy_address, StrategyData(TRUE, new_strategy_balance))

    let (current_total_strategy_holdings : Uint256) = total_strategy_holdings.read()
    let (new_total_strategy_holdings : Uint256) = uint256_checked_sub_le(
        current_total_strategy_holdings, underlying_amount
    )
    total_strategy_holdings.write(new_total_strategy_holdings)

    let (caller : felt) = get_caller_address()
    StrategyWithdrawal.emit(caller, strategy_address, underlying_amount)
    let (withdrawed_amount : Uint256) = IStrategy.redeemUnderlying(
        strategy_address, underlying_amount
    )
    let (is_zero : felt) = uint256_is_zero(withdrawed_amount)
    with_attr error_message("REDEEM_FAILED"):
        assert is_zero = FALSE
    end

    return ()
end

##############################################################################
#                     STRATEGY TRUST/DISTRUST LOGIC
##############################################################################

func trust_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt
):
    let (current_strategy_data : StrategyData) = strategy_data.read(strategy_address)
    strategy_data.write(strategy_address, StrategyData(TRUE, current_strategy_data.balance))
    let (caller : felt) = get_caller_address()
    StrategyTrusted.emit(caller, strategy_address)
    return ()
end

func distrust_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt
):
    let (current_strategy_data : StrategyData) = strategy_data.read(strategy_address)
    strategy_data.write(strategy_address, StrategyData(FALSE, current_strategy_data.balance))
    let (caller : felt) = get_caller_address()
    StrategyDistrusted.emit(caller, strategy_address)
    return ()
end

func Only_trusted_strategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt
):
    let (current_strategy_data : StrategyData) = strategy_data.read(strategy_address)
    with_attr error_message("UNTRUSTED_STRATEGY"):
        assert current_strategy_data.trusted = TRUE
    end
    return ()
end

##############################################################################
#                     FEE CLAIM LOGIC
##############################################################################
func claim_fees{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256
):
    let (contract_address : felt) = get_contract_address()
    let (caller : felt) = get_caller_address()
    IERC20.transfer(contract_address, caller, amount)
    FeesClaimed.emit(caller, amount)
    return ()
end
