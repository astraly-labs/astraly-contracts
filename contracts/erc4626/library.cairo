%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (
    ALL_ONES, Uint256, uint256_eq, uint256_add, uint256_mul, uint256_sub, uint256_unsigned_div_rem,
    uint256_le)

from openzeppelin.token.erc20.library import (
    ERC20_initializer, ERC20_totalSupply, ERC20_mint, ERC20_burn, ERC20_balanceOf, ERC20_allowances)
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.security.safemath import uint256_checked_mul, uint256_checked_div_rem

from contracts.utils import uint256_is_zero

@event
func Deposit(caller : felt, owner : felt, assets : Uint256, shares : Uint256):
end

@event
func Withdraw(caller : felt, receiver : felt, owner : felt, assets : Uint256, shares : Uint256):
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

#
# Initializer
#

func ERC4626_initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        name : felt, symbol : felt, asset_addr : felt):
    alloc_locals
    let (decimals) = IERC20.decimals(contract_address=asset_addr)
    ERC20_initializer(name, symbol, decimals)
    ERC4626_asset_addr.write(asset_addr)

    default_lock_time_days.write(365)
    return ()
end


#
# ERC4626
#

func ERC4626_asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        asset : felt):
    let (asset : felt) = ERC4626_asset_addr.read()
    return (asset)
end

func ERC4626_totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalManagedAssets : Uint256):
    let (asset : felt) = ERC4626_asset()
    let (vault : felt) = get_contract_address()
    let (total : Uint256) = IERC20.balanceOf(contract_address=asset, account=vault)
    return (total)
end

func ERC4626_convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assets : Uint256) -> (shares : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (assets)
    else:
        let (product : Uint256) = uint256_mul_checked(assets, total_supply)
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (shares, _) = uint256_unsigned_div_rem(product, total_assets)
        return (shares)
    end
end

func ERC4626_convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256) -> (assets : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (shares)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_mul_checked(shares, total_assets)
        let (assets, _) = uint256_unsigned_div_rem(product, total_supply)
        return (assets)
    end
end

#
# # Deposit
#

func ERC4626_maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        receiver : felt) -> (maxAssets : Uint256):
    let (maxAssets : Uint256) = uint256_max()
    return (maxAssets)
end

func ERC4626_previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assets : Uint256, lock_time : felt) -> (shares : Uint256):
    let (shares) = ERC4626_convertToShares(assets)
    let (result : Uint256) = calculate_lock_time_bonus(shares, lock_time)
    return (result)
end

func ERC4626_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assets : Uint256, receiver : felt, lock_time_days : felt) -> (shares : Uint256):
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
        contract_address=asset, sender=caller, recipient=vault, amount=assets)
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
        receiver : felt) -> (maxShares : Uint256):
    let (maxShares) = uint256_max()
    return (maxShares)
end

func ERC4626_previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256, lock_time : felt) -> (assets : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)
    let (bonus_removed : Uint256) = remove_lock_time_bonus(shares, lock_time)

    if is_total_supply_zero == TRUE:
        return (bonus_removed)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_mul_checked(bonus_removed, total_assets)
        let (assets) = uint256_unsigned_div_rem_up(product, total_supply)
        return (assets)
    end
end

func ERC4626_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256, receiver : felt) -> (assets : Uint256):
    alloc_locals
    
    let (default_lock_time : felt ) = default_lock_time_days.read()
    let (assets : Uint256) = ERC4626_previewMint(shares, default_lock_time)

    let (asset : felt) = ERC4626_asset()
    let (caller : felt) = get_caller_address()
    let (vault : felt) = get_contract_address()

    let (success : felt) = IERC20.transferFrom(
        contract_address=asset, sender=caller, recipient=vault, amount=assets)
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
        owner : felt) -> (maxAssets : Uint256):
    let (owner_balance : Uint256) = ERC20_balanceOf(owner)
    let (maxAssets : Uint256) = ERC4626_convertToAssets(owner_balance)
    return (maxAssets)
end

func ERC4626_previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assets : Uint256) -> (shares : Uint256):
    alloc_locals

    let (total_supply : Uint256) = ERC20_totalSupply()
    let (is_total_supply_zero : felt) = uint256_is_zero(total_supply)

    if is_total_supply_zero == TRUE:
        return (assets)
    else:
        let (total_assets : Uint256) = ERC4626_totalAssets()
        let (product : Uint256) = uint256_mul_checked(assets, total_supply)
        let (shares : Uint256) = uint256_unsigned_div_rem_up(product, total_assets)
        return (shares)
    end
end

func ERC4626_withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
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
        contract_address=asset, recipient=receiver, amount=assets)
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
        owner : felt) -> (maxShares : Uint256):
    let (maxShares : Uint256) = ERC20_balanceOf(owner)
    return (maxShares)
end

func ERC4626_previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256) -> (assets : Uint256):
    let (assets : Uint256) = ERC4626_convertToAssets(shares)
    return (assets)
end

func ERC4626_redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256, receiver : felt, owner : felt) -> (assets : Uint256):
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
        contract_address=asset, recipient=receiver, amount=assets)
    with_attr error_message("transfer failed"):
        assert success = TRUE
    end

    Withdraw.emit(caller=caller, receiver=receiver, owner=owner, assets=assets, shares=shares)

    return (assets)
end

#
# allowance helper
#

func decrease_allowance_by_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, spender : felt, amount : Uint256):
    alloc_locals

    let (spender_allowance : Uint256) = ERC20_allowances.read(owner, spender)

    let (max_allowance : Uint256) = uint256_max()
    let (is_max_allowance) = uint256_eq(spender_allowance, max_allowance)
    if is_max_allowance == 1:
        return ()
    end

    with_attr error_message("insufficient allowance"):
        # amount <= spender_allowance
        let (is_spender_allowance_sufficient) = uint256_le(amount, spender_allowance)
        assert is_spender_allowance_sufficient = 1
    end

    let (new_allowance : Uint256) = uint256_sub(spender_allowance, amount)
    ERC20_allowances.write(owner, spender, new_allowance)

    return ()
end

#
# Setters
#

# new_lock_time number of days
func set_default_lock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_lock_time_days : felt) -> ():
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
        shares : Uint256, lock_time : felt) -> (res : Uint256):
    let (value_multiplied : Uint256) = uint256_checked_mul(shares, Uint256(low=lock_time, high=0))
    let (res : Uint256, _) = uint256_checked_div_rem(value_multiplied, Uint256(low=730, high=0))
    return (res)
end

func remove_lock_time_bonus{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shares : Uint256, lock_time : felt) -> (res : Uint256):
    let (is_zero : felt) = uint256_is_zero(shares)
    if is_zero == TRUE:
        return (shares)
    end
    let (value_multiplied : Uint256) = uint256_checked_mul(shares, Uint256(low=730, high=0))
    let (res : Uint256, _) = uint256_checked_div_rem(value_multiplied, Uint256(low=lock_time, high=0))
    return (res)
end

#
# Uint256 helper functions
#
func uint256_max() -> (res : Uint256):
    return (Uint256(low=ALL_ONES, high=ALL_ONES))
end

func uint256_mul_checked{range_check_ptr}(a : Uint256, b : Uint256) -> (product : Uint256):
    alloc_locals

    let (product, carry) = uint256_mul(a, b)
    let (in_range) = uint256_is_zero(carry)
    with_attr error_message("number too big"):
        assert in_range = TRUE
    end
    return (product)
end

func uint256_unsigned_div_rem_up{range_check_ptr}(a : Uint256, b : Uint256) -> (res : Uint256):
    alloc_locals

    let (q, r) = uint256_unsigned_div_rem(a, b)
    let (reminder_is_zero : felt) = uint256_is_zero(r)

    if reminder_is_zero == TRUE:
        return (q)
    else:
        let (rounded_up, oof) = uint256_add(q, Uint256(low=1, high=0))
        with_attr error_message("rounding overflow"):
            assert oof = 0
        end
        return (rounded_up)
    end
end
