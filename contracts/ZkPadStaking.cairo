%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_lt, uint256_sub
from starkware.cairo.common.math import (
    assert_not_equal, assert_not_zero, assert_le, assert_lt, unsigned_div_rem)
from starkware.cairo.common.pow import pow
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import (
    get_caller_address, get_contract_address, get_block_timestamp)

from openzeppelin.utils.constants import TRUE, FALSE
from openzeppelin.access.ownable import Ownable_only_owner, Ownable_initializer, Ownable_get_owner
from openzeppelin.introspection.IERC165 import IERC165
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.security.safemath import (
    uint256_checked_add, uint256_checked_sub_lt, uint256_checked_sub_le, uint256_checked_mul, uint256_checked_div_rem)
from openzeppelin.security.pausable import Pausable_when_not_paused, Pausable_when_paused, Pausable_pause, Pausable_unpause

from contracts.openzeppelin.security.reentrancy_guard import (
    ReentrancyGuard_start, ReentrancyGuard_end)
from contracts.erc4626.ERC4626 import (
    name, symbol, totalSupply, decimals, balanceOf, allowance,
    asset, totalAssets, convertToShares, convertToAssets, maxDeposit, previewDeposit,
    maxMint, previewMint, maxWithdraw, previewWithdraw, maxRedeem, previewRedeem,
    ERC4626_withdraw, ERC4626_deposit, ERC4626_initializer, ERC4626_previewDeposit, ERC4626_redeem)
from openzeppelin.token.erc20.library import ERC20_approve, ERC20_burn, ERC20_transfer, ERC20_transferFrom, ERC20_mint
from contracts.utils import uint256_is_zero

const IERC721_ID = 0x80ac58cd

@contract_interface
namespace IMintCalculator:
    func get_amount_to_mint(input : Uint256) -> (amount : Uint256):
    end
end

struct WhitelistedToken:
    member bit_mask : felt
    member mint_calculator_address : felt
end
#
# Events
#
@event
func Deposit_lp(
        depositor : felt, receiver : felt, lp_address : felt, assets : Uint256, shares : Uint256):
end

@event
func Redeem_lp(
        receiver : felt, owner : felt, lp_token : felt, assets : Uint256, shares : Uint256):
end

#
# Storage variables
#

@storage_var
func whitelisted_tokens(lp_token : felt) -> (details : WhitelistedToken):
end

@storage_var
func token_mask_addresses(bit_mask : felt) -> (address : felt):
end

# bit mask with all whitelisted LP tokens
@storage_var
func whitelisted_tokens_mask() -> (mask : felt):
end

@storage_var
func deposits(user : felt, token_address : felt) -> (amount : Uint256):
end

@storage_var
func deposit_unlock_time(user : felt) -> (unlock_time : felt):
end

@storage_var
func user_staked_tokens(user : felt) -> (tokens_mask : felt):
end

# value is multiplied by 10 to store floating points number in felt type
@storage_var
func stake_boost() -> (boost : felt):
end

@storage_var
func default_lock_time() -> (lock_time : felt):
end

@storage_var
func emergency_breaker() -> (address : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        name : felt, symbol : felt, asset_addr : felt, owner : felt):
    ERC4626_initializer(name, symbol, asset_addr)
    Ownable_initializer(owner)

    default_lock_time.write(31536000) # 1 year

    # # Add ZKP token to the whitelist and bit mask on first position
    token_mask_addresses.write(1, asset_addr)
    whitelisted_tokens_mask.write(1)
    whitelisted_tokens.write(asset_addr, WhitelistedToken(1, 0))
    return ()
end

#
# View
#

@view
func is_token_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        lp_token : felt) -> (res : felt):
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    if whitelisted_token.bit_mask == 0:
        return (FALSE)
    end
    return (TRUE)
end

# Amount of xZKP a user will receive by providing LP token
@view
func get_xzkp_out{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        lp_token : felt, input : Uint256) -> (res : Uint256):
    alloc_locals
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    with_attr error_message("invalid mint calculator address"):
        assert_not_zero(whitelisted_token.mint_calculator_address)
    end
    with_attr error_message("invalid token amount or nft id"):
        let (is_zero) = uint256_is_zero(input)
        assert is_zero = FALSE
    end
    let (amount_to_mint : Uint256) = IMintCalculator.get_amount_to_mint(
        whitelisted_token.mint_calculator_address, input)

    let (current_boost : felt) = stake_boost.read()
    assert_not_zero(current_boost)
    let (value_multiplied : Uint256) = uint256_checked_mul(
        amount_to_mint, Uint256(0, current_boost))
    let (amount_after_boost : Uint256, _) = uint256_checked_div_rem(
        value_multiplied, Uint256(0, 10))

    return (amount_after_boost)
end

@view
func get_current_boost_value{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        ) -> (res : felt):
    let (res : felt) = stake_boost.read()
    return (res)
end

@view
func get_user_stake_info{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(user : felt) -> (unlock_time : felt, tokens_len : felt, tokens : felt*):
    alloc_locals
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    let (user_bit_mask : felt) = user_staked_tokens.read(user)

    let (staked_tokens_array : felt*) = alloc()
    let (array_len : felt) = get_tokens_addresses_from_mask(
        0, user_bit_mask, 0, staked_tokens_array)
    return (unlock_time, array_len, staked_tokens_array)
end

@view
func get_tokens_mask{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        tokens_mask : felt):
    let (bit_mask : felt) = whitelisted_tokens_mask.read()
    return (bit_mask)
end

@view
func get_default_lock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (lock_time : felt):
    let (lock_time : felt) = default_lock_time.read()
    return (lock_time)
end

func get_emergency_breaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (address : felt):
    let (address : felt) = emergency_breaker.read()
    return (address)
end
#
# Externals
#

@external
func add_whitelisted_token{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(lp_token : felt, mint_calculator_address : felt) -> (
        token_mask : felt):
    alloc_locals
    Ownable_only_owner()
    with_attr error_message("invalid token address"):
        assert_not_zero(lp_token)
    end
    with_attr error_message("invalid oracle address"):
        assert_not_zero(mint_calculator_address)
    end

    different_than_underlying(lp_token)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)

    with_attr error_message("already whitelisted"):
        assert whitelisted_token.bit_mask = 0
        assert whitelisted_token.mint_calculator_address = 0
    end

    let (tokens_masks : felt) = whitelisted_tokens_mask.read()

    let (token_mask : felt) = get_next_available_bit_in_mask(0, tokens_masks)
    whitelisted_tokens.write(lp_token, WhitelistedToken(token_mask, mint_calculator_address))
    token_mask_addresses.write(token_mask, lp_token)
    let (new_tokens_masks : felt) = bitwise_or(tokens_masks, token_mask)
    whitelisted_tokens_mask.write(new_tokens_masks)
    return (token_mask)
end

@external
func remove_whitelisted_token{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(lp_token : felt) -> ():
    Ownable_only_owner()
    let (all_token_masks : felt) = whitelisted_tokens_mask.read()
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (new_tokens_masks : felt) = bitwise_xor(whitelisted_token.bit_mask, all_token_masks)
    whitelisted_tokens_mask.write(new_tokens_masks)

    whitelisted_tokens.write(lp_token, WhitelistedToken(0, 0))
    token_mask_addresses.write(whitelisted_token.bit_mask, 0)
    return ()
end

@external
func set_emergency_breaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(address : felt) -> ():
    Ownable_only_owner()
    assert_not_zero(address)
    emergency_breaker.write(address)
    return ()
end

@external
func deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(
        assets : Uint256, receiver : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    let (shares) = ERC4626_deposit(assets, receiver)
    let (underlying_asset : felt) = asset()
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (default_lock_period : felt) = default_lock_time.read()
    set_new_deposit_unlock_time(receiver, current_block_timestamp + default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)
    return (shares)
end

@external
func deposit_for_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(
        assets : Uint256, receiver : felt, deadline : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    let (shares) = ERC4626_deposit(assets, receiver)
    set_new_deposit_unlock_time(receiver, deadline)
    let (underlying_asset : felt) = asset()
    update_user_after_deposit(receiver, underlying_asset, assets)
    return (shares)
end

## `input` should be the amount of tokens in case of an ERC20 or the id in case of ERC721
@external
func lp_deposit{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(
        lp_token : felt, input : Uint256, receiver : felt, deadline : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    set_new_deposit_unlock_time(receiver, deadline)

    let (caller_address : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (is_nft : felt) = IERC165.supportsInterface(lp_token, IERC721_ID)

    if is_nft == FALSE:
        let (success : felt) = IERC20.transferFrom(lp_token, caller_address, address_this, input)
        assert success = TRUE
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        let (id_is_zero : felt) = uint256_is_zero(input)
        with_attr error_message("invalid token id"):
            assert id_is_zero = FALSE
        end
        IERC721.transferFrom(lp_token, caller_address, address_this, input)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    let (amount_to_mint : Uint256) = get_xzkp_out(lp_token, input)
    ERC20_mint(receiver, amount_to_mint)
    update_user_after_deposit(receiver, lp_token, amount_to_mint)
    Deposit_lp.emit(caller_address, receiver, lp_token, input, amount_to_mint)
    ReentrancyGuard_end()
    return (amount_to_mint)
end

@external
func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(
        shares : Uint256, receiver : felt, owner : felt) -> (assets : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)
    let (assets : Uint256) = ERC4626_redeem(shares, receiver, owner)
    let (zkp_address : felt) = asset()
    update_mask_after_withdraw(owner, zkp_address)
    return (assets)
end

# lp_token is the LP token address user deposited first and get the xZKP tokens
# sharesAmount amount of xZKP tokens user want to redeem
@external
func redeem_lp{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(
        lp_token : felt, sharesAmount : Uint256, receiver : felt) -> ():
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    let (owner : felt) = get_caller_address()
    assert_not_before_unlock_time(owner)
    
    let (address_this : felt) = get_contract_address()
    let (contract_lp_balance : Uint256) = IERC20.balanceOf(lp_token, address_this)
    let (enought_token_balance : felt) = uint256_le(sharesAmount, contract_lp_balance)

    if enought_token_balance == FALSE:
        let (amount_to_withdraw : Uint256) = uint256_sub(sharesAmount, contract_lp_balance)
        withdraw_from_investment_strategies(lp_token, amount_to_withdraw)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    ERC20_burn(owner, sharesAmount)
    let (user_current_deposit_amount : Uint256) = deposits.read(receiver, lp_token)
    let (lp_withdraw_amount : Uint256) = calculate_withdraw_lp_amount(owner, lp_token, sharesAmount)

    let (withdraw_more_than_deposit : felt) = uint256_lt(user_current_deposit_amount, lp_withdraw_amount) # allow, user earned fees
    if withdraw_more_than_deposit == TRUE:
        deposits.write(receiver, lp_token, Uint256(0,0))
        update_mask_after_withdraw(owner, lp_token)
    else:
        let (new_user_deposit_amount : Uint256) = uint256_checked_sub_le(user_current_deposit_amount, lp_withdraw_amount)
        deposits.write(receiver, lp_token, new_user_deposit_amount)
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end

    let (success : felt) = IERC20.transfer(lp_token, receiver, lp_withdraw_amount)
    assert success = TRUE
    Redeem_lp.emit(receiver, owner, lp_token, lp_withdraw_amount, sharesAmount)
    ReentrancyGuard_end()
    return ()
end

@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(
        assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)
    let (shares : Uint256) = ERC4626_withdraw(assets, receiver, owner)
    let (zkp_address : felt) = asset()
    update_mask_after_withdraw(owner, zkp_address)
    return (shares)
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        recipient : felt, amount : Uint256) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    ERC20_transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        sender : felt, recipient : felt, amount : Uint256) -> (success : felt):
    Pausable_when_not_paused()
    assert_not_before_unlock_time(sender)
    ERC20_transferFrom(sender, recipient, amount)
    return (TRUE)
end

@external
func set_stake_boost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        new_boost_value : felt) -> ():
    Ownable_only_owner()
    assert_not_zero(new_boost_value)
    stake_boost.write(new_boost_value)
    return ()
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        spender : felt, amount : Uint256) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    ERC20_approve(spender, amount)
    return (TRUE)
end

@external
func set_default_lock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_lock_time : felt) -> ():
    Ownable_only_owner()
    default_lock_time.write(new_lock_time)
    return ()
end

@external
func pause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (emergency_breaker_address : felt) = emergency_breaker.read()
    let (owner : felt ) = Ownable_get_owner()
    local permissions
    if owner == caller_address:
        permissions = TRUE
    end
    if emergency_breaker_address == caller_address:
        permissions = TRUE # either owner or emergency breaker have permission to pause the contract
    end
    with_attr error_message("invalid permissions"):
        assert permissions = TRUE
    end
    Pausable_pause()
    return ()
end

@external
func unpause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    Ownable_only_owner()
    Pausable_unpause()
    return ()
end

#
# Internal
#

func only_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        address : felt) -> ():
    let (res : WhitelistedToken) = whitelisted_tokens.read(address)
    with_attr error_message("token not whitelisted"):
        assert_not_zero(res.mint_calculator_address)
        assert_not_zero(res.bit_mask)
    end
    return ()
end

func different_than_underlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        address : felt) -> ():
    with_attr error_message("underlying token not allow"):
        let (underlying_asset : felt) = asset()
        assert_not_equal(underlying_asset, address)
    end
    return ()
end

func withdraw_from_investment_strategies{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        lp_token_address : felt, amount : Uint256) -> ():
    # TODO: implement
    return ()
end

# return the first available bit in the mask
func get_next_available_bit_in_mask{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(index : felt, bit_mask : felt) -> (res : felt):
    let (value : felt) = pow(2, index)
    let (and_result : felt) = bitwise_and(value, bit_mask)
    if and_result == 0:
        return (value)
    end

    return get_next_available_bit_in_mask(index + 1, bit_mask)
end

func get_tokens_addresses_from_mask{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(
        position : felt, bit_mask : felt, tokens_allocation_index : felt, array : felt*) -> (
        length : felt):
    alloc_locals
    if bit_mask == 0:
        return (tokens_allocation_index)
    end

    let (bit_mask_left : felt, remainder : felt) = unsigned_div_rem(bit_mask, 2)
    if remainder == 1:
        let (token_mask : felt) = pow(2, position)
        let (token_address : felt) = token_mask_addresses.read(token_mask)
        assert [array + tokens_allocation_index] = token_address
        return get_tokens_addresses_from_mask(
            position + 1, bit_mask_left, tokens_allocation_index + 1, array)
    end
    return get_tokens_addresses_from_mask(
        position + 1, bit_mask_left, tokens_allocation_index, array)
end

func add_token_to_user_mask{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        bitwise_ptr : BitwiseBuiltin*}(user : felt, token : felt) -> ():
    let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
    let (new_user_tokens_mask : felt) = bitwise_or(
        user_current_tokens_mask, whitelisted_token.bit_mask)
    user_staked_tokens.write(user, new_user_tokens_mask)
    return ()
end

func assert_not_before_unlock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> ():
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    with_attr error_message("timestamp {current_block_timestamp} lower than deposit unlock time {unlock_time}"):
        assert_le(unlock_time, current_block_timestamp)
    end
    return ()
end

func calculate_withdraw_lp_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, lp_token : felt, sharesAmount : Uint256) -> (amount : Uint256):
    # TODO: calculate user return
    let (multiplied : Uint256) = uint256_checked_mul(sharesAmount, Uint256(0, 10))
    let (current_boost : felt) = stake_boost.read()
    let (res : Uint256, _) = uint256_checked_div_rem(multiplied, Uint256(0, current_boost))
    return (res)
end

func set_new_deposit_unlock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user :felt, deadline : felt) -> ():
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    with_attr error_message("new deadline should be higher or equal to the old deposit"):
        assert_le(unlock_time, deadline)
    end

    with_attr error_message("new deadline should be higher than current timestamp"):
        assert_lt(current_block_timestamp, deadline)
    end
    deposit_unlock_time.write(user, deadline)
    return ()
end

# update user deposit info and staked tokens bit mask
func update_user_after_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(
        user : felt, token : felt, new_amount : Uint256) -> ():
    alloc_locals
    let (current_deposit_amount : Uint256) = deposits.read(user, token)
    let (new_deposit_amount : Uint256) = uint256_checked_add(current_deposit_amount, new_amount)
    deposits.write(user, token, new_deposit_amount)


    let (is_first_deposit : felt) = uint256_is_zero(current_deposit_amount)
    if is_first_deposit == TRUE:
        add_token_to_user_mask(user, token)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end
    return ()
end

# remove user staked tokens from the bit mask is new balance is 0
func update_mask_after_withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(user : felt, token : felt) -> ():
    alloc_locals
    let (current_user_deposit : Uint256) = deposits.read(user, token)
    let (withdraw_all_tokens : felt) = uint256_is_zero(current_user_deposit)
    if withdraw_all_tokens == TRUE:
        let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
        let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
        let (new_user_tokens_mask : felt) = bitwise_xor(
            user_current_tokens_mask, whitelisted_token.bit_mask)
        user_staked_tokens.write(user, new_user_tokens_mask)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end
    return ()
end
