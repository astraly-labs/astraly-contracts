%lang starknet

from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.math import assert_le, assert_not_zero
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (
    ALL_ONES,
    Uint256,
    uint256_eq,
    uint256_add,
    uint256_mul,
    uint256_sub,
    uint256_unsigned_div_rem,
    uint256_le,
    uint256_lt,
)
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow

from openzeppelin.token.erc20.library import (
    ERC20_initializer,
    ERC20_totalSupply,
    ERC20_mint,
    ERC20_burn,
    ERC20_balanceOf,
    ERC20_allowances,
)

from openzeppelin.security.safemath import (
    uint256_checked_mul,
    uint256_checked_div_rem,
    uint256_checked_sub_le,
    uint256_checked_add,
    uint256_checked_sub_lt,
)

from contracts.utils import get_array, uint256_is_zero, mul_div_down
from InterfaceAll import IERC20

@event
func Deposit(caller : felt, owner : felt, assets : Uint256, shares : Uint256):
end

@event
func Withdraw(caller : felt, receiver : felt, owner : felt, assets : Uint256, shares : Uint256):
end

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

#
# Storage
#

@storage_var
func ERC4626_asset_addr() -> (addr : felt):
end

@storage_var
func default_lock_time_days() -> (lock_time : felt):
end

# # @notice A timestamp representing when the most recent harvest occurred.
@storage_var
func last_harvest() -> (harvest : felt):
end

@storage_var
func harvest_delay() -> (delay : felt):
end

# # @notice The amount of locked profit at the end of the last harvest.
@storage_var
func max_locked_profit() -> (profit : Uint256):
end

# # @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
# # @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
@storage_var
func total_strategy_holdings() -> (holdings : Uint256):
end

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
func next_harvest_delay() -> (delay : felt):
end

# # @notice The desired float percentage of holdings.
# # @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
@storage_var
func target_float_percent() -> (percent : felt):
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

# # @notice An ordered array of strategies representing the withdrawal queue.
# # @dev The queue is processed in descending order.
# # @dev Returns a tupled-array of (array_len, Strategy[])
@storage_var
func withdrawal_queue(index : felt) -> (strategy_address : felt):
end

@storage_var
func withdrawal_queue_length() -> (length : felt):
end

#
# Initializer
#

func ERC4626_initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, asset_addr : felt
):
    alloc_locals
    let (decimals) = IERC20.decimals(contract_address=asset_addr)
    ERC20_initializer(name, symbol, decimals)
    ERC4626_asset_addr.write(asset_addr)
    return ()
end

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
    let (underlying : felt) = ERC4626_asset()
    let (address_this : felt) = get_contract_address()
    let (balance_of_this : Uint256) = IERC20.balanceOf(underlying, address_this)

    return (balance_of_this)
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

@view
func lastHarvest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    time : felt
):
    let (time : felt) = last_harvest.read()
    return (time)
end

@view
func lastHarvestWindowStart{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    ) -> (res : felt):
    let (res : felt) = last_harvest_window_start.read()
    return (res)
end

@view
func nextHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    delay : felt
):
    let (res : felt) = next_harvest_delay.read()
    return (res)
end

#
# ERC4626
#

func ERC4626_asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    asset : felt
):
    let (asset : felt) = ERC4626_asset_addr.read()
    return (asset)
end

func ERC4626_totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalManagedAssets : Uint256
):
    alloc_locals
    let (locked_profit : Uint256) = lockedProfit()
    let (current_total_strategy_holdings : Uint256) = total_strategy_holdings.read()
    let (total_underlying_held : Uint256) = uint256_checked_sub_le(
        current_total_strategy_holdings, locked_profit
    )
    let (total_float : Uint256) = totalFloat()
    let (add_float : Uint256) = uint256_checked_add(total_underlying_held, total_float)
    return (add_float)
end

func ERC4626_convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (assets)
    else:
        let (product : Uint256) = uint256_checked_mul(assets, total_supply)
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (shares, _) = uint256_unsigned_div_rem(product, total_assets)
        return (shares)
    end
end

func ERC4626_convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (shares)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_checked_mul(shares, total_assets)
        let (assets, _) = uint256_unsigned_div_rem(product, total_supply)
        return (assets)
    end
end

#
# # Deposit
#

func ERC4626_maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    receiver : felt
) -> (maxAssets : Uint256):
    let (maxAssets : Uint256) = uint256_max()
    return (maxAssets)
end

func ERC4626_previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256, lock_time : felt
) -> (shares : Uint256):
    let (shares) = ERC4626_convertToShares(assets)
    let (result : Uint256) = calculate_lock_time_bonus(shares, lock_time)
    return (result)
end

func ERC4626_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256, receiver : felt, lock_time_days : felt
) -> (shares : Uint256):
    alloc_locals

    let (shares : Uint256) = ERC4626_previewDeposit(assets, lock_time_days)
    let (shares_is_zero : felt) = uint256_is_zero(shares)
    with_attr error_message("zero shares"):
        assert shares_is_zero = FALSE
    end

    let (asset : felt) = ERC4626_asset()
    let (caller : felt) = get_caller_address()
    let (vault : felt) = get_contract_address()

    let (success : felt) = IERC20.transferFrom(
        contract_address=asset, sender=caller, recipient=vault, amount=assets
    )
    with_attr error_message("transfer failed"):
        assert success = TRUE
    end

    ERC20_mint(receiver, shares)

    Deposit.emit(caller=caller, owner=receiver, assets=assets, shares=shares)

    return (shares)
end

#
# # Mint
#

func ERC4626_maxMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    receiver : felt
) -> (maxShares : Uint256):
    let (maxShares) = uint256_max()
    return (maxShares)
end

func ERC4626_previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (assets : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)
    let (bonus_removed : Uint256) = remove_lock_time_bonus(shares, lock_time)

    if is_total_supply_zero == TRUE:
        return (bonus_removed)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_checked_mul(bonus_removed, total_assets)
        let (assets, _) = uint256_checked_div_rem(product, total_supply)
        return (assets)
    end
end

func ERC4626_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, receiver : felt
) -> (assets : Uint256):
    alloc_locals

    let (default_lock_time : felt) = default_lock_time_days.read()
    let (assets : Uint256) = ERC4626_previewMint(shares, default_lock_time)

    let (asset : felt) = ERC4626_asset()
    let (caller : felt) = get_caller_address()
    let (vault : felt) = get_contract_address()

    let (success : felt) = IERC20.transferFrom(
        contract_address=asset, sender=caller, recipient=vault, amount=assets
    )
    with_attr error_message("transfer failed"):
        assert success = TRUE
    end

    ERC20_mint(receiver, shares)

    Deposit.emit(caller=caller, owner=receiver, assets=assets, shares=shares)

    return (assets)
end

#
# # Withdraw
#

func ERC4626_maxWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt
) -> (maxAssets : Uint256):
    let (owner_balance : Uint256) = ERC20_balanceOf(owner)
    let (maxAssets : Uint256) = ERC4626_convertToAssets(owner_balance)
    return (maxAssets)
end

func ERC4626_previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (assets)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_checked_mul(assets, total_supply)
        let (shares : Uint256, _) = uint256_checked_div_rem(product, total_assets)
        return (shares)
    end
end

func ERC4626_withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256, receiver : felt, owner : felt
) -> (shares : Uint256):
    alloc_locals

    let (shares : Uint256) = ERC4626_previewWithdraw(assets)

    let (caller : felt) = get_caller_address()

    if caller != owner:
        decrease_allowance_by_amount(owner, caller, shares)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    ERC20_burn(owner, shares)

    let (asset : felt) = ERC4626_asset()
    let (success : felt) = IERC20.transfer(
        contract_address=asset, recipient=receiver, amount=assets
    )
    with_attr error_message("transfer failed"):
        assert success = TRUE
    end

    Withdraw.emit(caller=caller, receiver=receiver, owner=owner, assets=assets, shares=shares)

    return (shares)
end

#
# # REDEEM
#

func ERC4626_maxRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt
) -> (maxShares : Uint256):
    let (maxShares : Uint256) = ERC20_balanceOf(owner)
    return (maxShares)
end

func ERC4626_previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (assets : Uint256) = ERC4626_convertToAssets(shares)
    return (assets)
end

func ERC4626_redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, receiver : felt, owner : felt
) -> (assets : Uint256):
    alloc_locals

    let (caller : felt) = get_caller_address()

    if caller != owner:
        decrease_allowance_by_amount(owner, caller, shares)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    let (assets : Uint256) = ERC4626_previewRedeem(shares)
    let (is_zero_assets : felt) = uint256_is_zero(assets)
    with_attr error_message("zero assets"):
        assert is_zero_assets = FALSE
    end

    ERC20_burn(owner, shares)

    let (asset : felt) = ERC4626_asset()
    let (success : felt) = IERC20.transfer(
        contract_address=asset, recipient=receiver, amount=assets
    )
    with_attr error_message("transfer failed"):
        assert success = TRUE
    end

    Withdraw.emit(caller=caller, receiver=receiver, owner=owner, assets=assets, shares=shares)

    return (assets)
end

#
# allowance helper
#

func decrease_allowance_by_amount{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(owner : felt, spender : felt, amount : Uint256):
    alloc_locals

    let (spender_allowance : Uint256) = ERC20_allowances.read(owner, spender)

    let (max_allowance : Uint256) = uint256_max()
    let (is_max_allowance) = uint256_eq(spender_allowance, max_allowance)
    if is_max_allowance == TRUE:
        return ()
    end

    with_attr error_message("insufficient allowance"):
        # amount <= spender_allowance
        let (is_spender_allowance_sufficient) = uint256_le(amount, spender_allowance)
        assert is_spender_allowance_sufficient = TRUE
    end

    let (new_allowance : Uint256) = uint256_sub(spender_allowance, amount)
    ERC20_allowances.write(owner, spender, new_allowance)

    return ()
end

#
# Setters
#

# new_lock_time number of days
func set_default_lock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_lock_time_days : felt
) -> ():
    default_lock_time_days.write(new_lock_time_days)
    return ()
end

func days_to_seconds{syscall_ptr : felt*, range_check_ptr}(days : felt) -> (seconds : felt):
    let (hours : felt) = safe_multiply(days, 24)
    let (minutes : felt) = safe_multiply(hours, 60)
    let (seconds : felt) = safe_multiply(minutes, 60)
    return (seconds)
end

func safe_multiply{syscall_ptr : felt*, range_check_ptr}(a : felt, b : felt) -> (result : felt):
    if a == 0:
        return (0)
    end
    if b == 0:
        return (0)
    end
    let res : felt = a * b
    assert_le(a, res)
    assert_le(b, res)
    return (res)
end

func calculate_lock_time_bonus{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (res : Uint256):
    let (value_multiplied : Uint256) = uint256_checked_mul(shares, Uint256(low=lock_time, high=0))
    let (res : Uint256, _) = uint256_checked_div_rem(value_multiplied, Uint256(low=730, high=0))
    return (res)
end

func remove_lock_time_bonus{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (res : Uint256):
    let (is_zero : felt) = uint256_is_zero(shares)
    if is_zero == TRUE:
        return (shares)
    end
    let (value_multiplied : Uint256) = uint256_checked_mul(shares, Uint256(low=730, high=0))
    let (res : Uint256, _) = uint256_checked_div_rem(
        value_multiplied, Uint256(low=lock_time, high=0)
    )
    return (res)
end

#
# Uint256 helper functions
#
func uint256_max() -> (res : Uint256):
    return (Uint256(low=ALL_ONES, high=ALL_ONES))
end

####################################################################################
#                                   Investment Strategy Logic
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
    new_harvest_window : felt
):
    let (delay) = harvest_delay.read()
    with_attr error_message("WINDOW_TOO_LONG"):
        assert_le(new_harvest_window, delay)
    end
    harvest_window.write(new_harvest_window)
    let (caller : felt) = get_caller_address()
    HarvestDelayUpdated.emit(caller, new_harvest_window)
    return ()
end

# # @notice Sets a new harvest delay.
# # @param newHarvestDelay The new harvest delay.
func set_harvest_delay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_delay : felt
):
    alloc_locals
    with_attr error_message("DELAY_CANNOT_BE_ZERO"):
        assert_not_zero(new_delay)
    end

    with_attr error_message("DELAY_TOO_LONG"):
        assert_le(new_delay, 31536000)  # 31,536,000 = 365 days = 1 year
    end

    let (caller : felt) = get_caller_address()
    let (local delay) = harvest_delay.read()
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
    let (current_locked_profit : Uint256) = lockedProfit()

    let (address_this : felt) = get_contract_address()
    let (total_profit_accrued : Uint256, new_total_strategy_holdings : Uint256) = _check_strategies(
        strategies_len, strategies, 0, Uint256(0, 0), old_total_strategy_holdings, address_this
    )
    let (no_fees_earned : felt) = uint256_is_zero(total_profit_accrued)

    if no_fees_earned == TRUE:
        let (sum : Uint256) = uint256_checked_add(current_locked_profit, total_profit_accrued)
        max_locked_profit.write(sum)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        let (current_fee_percent : felt) = fee_percent.read()
        let (fees_accrued : Uint256) = mul_div_down(
            total_profit_accrued, Uint256(current_fee_percent, 0), Uint256(10 ** 18, 0)
        )
        let (new_max_locked_profit : Uint256) = uint256_sub(total_profit_accrued, fees_accrued)
        max_locked_profit.write(new_max_locked_profit)
        let (base_unit_value : felt) = base_unit.read()
        let (base_unit_to_asset : Uint256) = ERC4626_convertToAssets(Uint256(base_unit_value, 0))
        let (value_to_mint : Uint256) = mul_div_down(
            fees_accrued, Uint256(base_unit_value, 0), base_unit_to_asset
        )
        ERC20_mint(address_this, value_to_mint)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

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
    address_this : felt,
) -> (total_profit_accrued : Uint256, total_strategy_holdings : Uint256):
    alloc_locals
    if index == strategies_len:
        return (total_profit_accrued, total_strategy_holdings)
    end
    Only_trusted_strategy(strategies[index])
    let (current_strategy_data : StrategyData) = strategy_data.read(strategies[index])
    let (underlying_asset : felt) = ERC4626_asset()
    let balance_last_harvest : Uint256 = current_strategy_data.balance
    let (balance_this_harvest : Uint256) = IStrategy.balanceOfUnderlying(
        strategies[index], address_this
    )

    strategy_data.write(strategies[index], StrategyData(TRUE, balance_this_harvest))

    let (sum : Uint256) = uint256_checked_add(total_strategy_holdings, balance_this_harvest)
    let (new_total_strategy_holdings : Uint256) = uint256_checked_sub_le(sum, balance_last_harvest)

    let (is_last_harvest_balance_lt : felt) = uint256_lt(balance_last_harvest, balance_this_harvest)
    if is_last_harvest_balance_lt == TRUE:
        let (profit : Uint256) = uint256_checked_sub_lt(balance_this_harvest, balance_last_harvest)
        let (new_total_profit_accrued : Uint256) = uint256_checked_add(total_profit_accrued, profit)
        return _check_strategies(
            strategies_len,
            strategies,
            index + 1,
            new_total_profit_accrued,
            new_total_strategy_holdings,
            address_this,
        )
    else:
        return _check_strategies(
            strategies_len,
            strategies,
            index + 1,
            total_profit_accrued,
            new_total_strategy_holdings,
            address_this,
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

    let (underlying_asset : felt) = ERC4626_asset()
    IERC20.approve(underlying_asset, strategy_address, underlying_amount)

    let (minted : Uint256) = IStrategy.mint(strategy_address, underlying_amount)
    with_attr error_message("MINT_FAILED"):
        let (minted_zero_tokens : felt) = uint256_is_zero(minted)
        assert minted_zero_tokens = FALSE
    end

    withdrawal_queue_length.write(1)  # Suport only one strategy for now
    withdrawal_queue.write(0, strategy_address)

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
    let (zero_withdrawn : felt) = uint256_is_zero(withdrawed_amount)
    with_attr error_message("REDEEM_FAILED"):
        assert zero_withdrawn = FALSE
    end

    return ()
end

func check_enough_underlying_balance{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(amount_to_withdraw : Uint256):
    alloc_locals
    let (address_this : felt) = get_contract_address()
    let (underlying : felt) = ERC4626_asset()
    let (contract_balance : Uint256) = IERC20.balanceOf(underlying, address_this)
    let (not_enough_balance_in_contract : felt) = uint256_lt(contract_balance, amount_to_withdraw)
    if not_enough_balance_in_contract == TRUE:
        let (_, withdrawal_queue : felt*) = getWithdrawalQueue()
        let (withdraw_amount_required : Uint256) = uint256_checked_sub_lt(
           amount_to_withdraw, contract_balance)
        let first_strategy : felt = withdrawal_queue[0]
        assert_not_zero(first_strategy)
        let (strategy_details : StrategyData) = strategy_data.read(first_strategy)
        
        let (enough_balance_in_strategy : felt) = uint256_le(withdraw_amount_required, strategy_details.balance)
        
        if enough_balance_in_strategy == TRUE:
            withdraw_from_strategy(first_strategy, withdraw_amount_required)
            return ()
        else:
            let (address_this) = get_contract_address()
            let (strategy_balance_is_zero : felt) = uint256_is_zero(strategy_details.balance)
            if strategy_balance_is_zero == TRUE:
                IERC20.mint(underlying, address_this, withdraw_amount_required)
                return ()
            else:
                let (remaining_amount : Uint256) = uint256_checked_sub_le(withdraw_amount_required, strategy_details.balance)
                IERC20.mint(underlying, address_this, remaining_amount)
                return ()
            end
        end
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
