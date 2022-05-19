%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_le,
    uint256_lt,
    uint256_sub,
    uint256_check,
    uint256_eq,
)
from starkware.cairo.common.math import (
    assert_not_equal,
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
)
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.pow import pow
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
    get_block_number,
)

from openzeppelin.access.ownable import Ownable_only_owner, Ownable_initializer, Ownable_get_owner
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_lt,
    uint256_checked_sub_le,
    uint256_checked_mul,
    uint256_checked_div_rem,
)
from openzeppelin.security.pausable import (
    Pausable_when_not_paused,
    Pausable_when_paused,
    Pausable_pause,
    Pausable_unpause,
)
from openzeppelin.token.erc20.library import (
    ERC20_approve,
    ERC20_burn,
    ERC20_transfer,
    ERC20_transferFrom,
    ERC20_mint,
)
from contracts.openzeppelin.security.reentrancy_guard import (
    ReentrancyGuard_start,
    ReentrancyGuard_end,
)
from openzeppelin.upgrades.library import (
    Proxy_only_admin,
    Proxy_initializer,
    Proxy_get_implementation,
    Proxy_set_implementation,
)

from contracts.erc4626.ERC4626 import (
    name,
    symbol,
    totalSupply,
    decimals,
    balanceOf,
    allowance,
    asset,
    convertToShares,
    convertToAssets,
    maxDeposit,
    maxMint,
    maxWithdraw,
    previewWithdraw,
    previewDeposit,
    previewMint,
    previewMintForTime,
    maxRedeem,
    totalAssets,
    previewRedeem,
    ERC4626_withdraw,
    ERC4626_deposit,
    ERC4626_initializer,
    ERC4626_redeem,
    ERC4626_mint,
    ERC4626_convertToShares,
    decrease_allowance_by_amount,
    set_default_lock_time,
    days_to_seconds,
    calculate_lock_time_bonus,
    default_lock_time_days,
)
from contracts.erc4626.library import (
    getWithdrawalQueue,
    totalFloat,
    lockedProfit,
    feePercent,
    harvestDelay,
    harvestWindow,
    nextHarvestDelay,
    targetFloatPercent,
    totalStrategyHoldings,
    lastHarvestWindowStart,
    lastHarvest,
    set_fee_percent,
    set_harvest_window,
    set_harvest_delay,
    set_target_float_percent,
    set_base_unit,
    harvest_investment,
    deposit_into_strategy,
    withdraw_from_strategy,
    trust_strategy,
    distrust_strategy,
    claim_fees,
)
from contracts.utils import uint256_is_zero, and
from contracts.utils.Uint256_felt_conv import _felt_to_uint

# from contracts.ZkPadStrategyManager import constructor

@contract_interface
namespace IMintCalculator:
    func getPoolAddress() -> (address : felt):
    end

    func getAmountToMint(input : Uint256) -> (amount : Uint256):
    end
end

@contract_interface
namespace IVault:
    func feePercent() -> (fee_percent : felt):
    end

    func harvestDelay() -> (harvest_delay : felt):
    end

    func harvestWindow() -> (harvest_window : felt):
    end

    func targetFloatPercent() -> (float_percent : felt):
    end

    func setFeePercent(new_fee_percent : felt):
    end

    func setHarvestDelay(new_harvest_delay : felt):
    end

    func setHarvestWindow(new_harvest_window : felt):
    end

    func setTargetFloatPercent(float_percent : felt):
    end

    func initializer(name : felt, symbol : felt, asset_addr : felt, owner : felt):
    end
end

struct WhitelistedToken:
    member bit_mask : felt
    member mint_calculator_address : felt
    member is_NFT : felt
end

struct UserInfo:
    member amount : Uint256
    member rewardDebt : Uint256
end

#
# Events
#
@event
func DepositLP(
    depositor : felt, receiver : felt, lp_address : felt, assets : Uint256, shares : Uint256
):
end

@event
func WithdrawLP(
    caller : felt,
    receiver : felt,
    owner : felt,
    lp_token : felt,
    assets : Uint256,
    shares : Uint256,
):
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
func lp_stake_boost() -> (boost : felt):
end

@storage_var
func emergency_breaker() -> (address : felt):
end

#
# View
#

@view
func isTokenWhitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt
) -> (res : felt):
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    if whitelisted_token.bit_mask == 0:
        return (FALSE)
    end
    return (TRUE)
end

@view
func previewDepositForTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256, lock_time : felt
) -> (shares : Uint256):
    let (shares : Uint256) = ERC4626_convertToShares(assets)
    let (result : Uint256) = calculate_lock_time_bonus(shares, lock_time)
    return (result)
end

# Amount of xZKP a user will receive by providing LP token
# lp_token Address of the ZKP/ETH LP token
# assets Amount of LP tokens or the NFT id
# lock_time Number of days user lock the tokens
@view
func previewDepositLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, assets : Uint256, lock_time : felt
) -> (shares : Uint256):
    alloc_locals
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    with_attr error_message("invalid mint calculator address"):
        assert_not_zero(whitelisted_token.mint_calculator_address)
    end
    with_attr error_message("invalid token amount or nft id"):
        let (is_zero) = uint256_is_zero(assets)
        assert is_zero = FALSE
    end
    # convert to ZKP
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        whitelisted_token.mint_calculator_address, assets
    )
    let (shares : Uint256) = previewDepositForTime(zkp_quote, lock_time)
    let (current_lp_boost : felt) = lp_stake_boost.read()
    if current_lp_boost == 0:
        return (shares)
    end
    let (applied_boost : Uint256) = uint256_checked_mul(shares, Uint256(current_lp_boost, 0))
    let (res : Uint256, _) = uint256_checked_div_rem(applied_boost, Uint256(10, 0))
    return (res)
end

@view
func getCurrentBoostValue{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (res : felt) = lp_stake_boost.read()
    return (res)
end

@view
func getUserStakeInfo{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt) -> (unlock_time : felt, tokens_len : felt, tokens : felt*):
    alloc_locals
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    let (user_bit_mask : felt) = user_staked_tokens.read(user)

    let (staked_tokens_array : felt*) = alloc()
    let (array_len : felt) = get_tokens_addresses_from_mask(
        0, user_bit_mask, 0, staked_tokens_array
    )
    return (unlock_time, array_len, staked_tokens_array)
end

@view
func getTokensMask{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    tokens_mask : felt
):
    let (bit_mask : felt) = whitelisted_tokens_mask.read()
    return (bit_mask)
end

@view
func getEmergencyBreaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (address : felt) = emergency_breaker.read()
    return (address)
end

@view
func getImplementation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (address) = Proxy_get_implementation()
    return (address)
end

@view
func previewRedeemLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, shares : Uint256
) -> (amount : Uint256):
    alloc_locals
    only_whitelisted_token(lp_token)
    let (caller_address : felt) = get_caller_address()
    let (lp_withdraw_amount : Uint256) = calculate_withdraw_lp_amount(
        caller_address, lp_token, shares
    )
    return (lp_withdraw_amount)
end

@view
func previewWithdrawLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, input : Uint256
) -> (amount : Uint256):
    only_whitelisted_token(lp_token)
    let (caller_address : felt) = get_caller_address()
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (output : Uint256) = IMintCalculator.getAmountToMint(
        whitelisted_token.mint_calculator_address, input
    )
    return (output)
end

@view
func getDefaultLockTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    lock_time : felt
):
    let (lock_time : felt) = default_lock_time_days.read()
    return (lock_time)
end

#
# Externals
#

@external
func initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, asset_addr : felt, owner : felt
):
    alloc_locals
    assert_not_zero(owner)
    Proxy_initializer(owner)
    ERC4626_initializer(name, symbol, asset_addr)
    Ownable_initializer(owner)
    set_base_unit(asset_addr)
    setDefaultLockTime(365)
    setStakeBoost(25)
    setFeePercent(1)  # TODO : Check division later

    # # Add ZKP token to the whitelist and bit mask on first position
    token_mask_addresses.write(1, asset_addr)
    whitelisted_tokens_mask.write(1)
    whitelisted_tokens.write(asset_addr, WhitelistedToken(1, 0, FALSE))
    return ()
end

@external
func upgrade{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_implementation : felt
):
    Proxy_only_admin()
    Proxy_set_implementation(new_implementation)
    return ()
end

@external
func addWhitelistedToken{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, mint_calculator_address : felt, is_NFT : felt) -> (token_mask : felt):
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
    whitelisted_tokens.write(
        lp_token, WhitelistedToken(token_mask, mint_calculator_address, is_NFT)
    )
    token_mask_addresses.write(token_mask, lp_token)
    let (new_tokens_masks : felt) = bitwise_or(tokens_masks, token_mask)
    whitelisted_tokens_mask.write(new_tokens_masks)
    return (token_mask)
end

@external
func removeWhitelistedToken{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt):
    Ownable_only_owner()
    let (all_token_masks : felt) = whitelisted_tokens_mask.read()
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (new_tokens_masks : felt) = bitwise_xor(whitelisted_token.bit_mask, all_token_masks)
    whitelisted_tokens_mask.write(new_tokens_masks)

    whitelisted_tokens.write(lp_token, WhitelistedToken(0, 0, FALSE))
    token_mask_addresses.write(whitelisted_token.bit_mask, 0)
    return ()
end

@external
func setEmergencyBreaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    Ownable_only_owner()
    assert_not_zero(address)
    emergency_breaker.write(address)
    return ()
end

@external
func deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    # Update pool
    _updatePool()

    let (default_lock_time : felt) = default_lock_time_days.read()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, default_lock_time)
    let (underlying_asset : felt) = asset()
    let (default_lock_period : felt) = getDefaultLockTime()
    set_new_deposit_unlock_time(receiver, default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)

    # Update user info
    let (cur_user_info : UserInfo) = userInfo.read(receiver)
    let (new_amount : Uint256) = uint256_checked_add(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=cur_user_info.rewardDebt)
    userInfo.write(receiver, new_user_info)

    ReentrancyGuard_end()
    return (shares)
end

# `lock_time_days` number of days
@external
func depositForTime{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt, lock_time_days : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, lock_time_days)
    set_new_deposit_unlock_time(receiver, lock_time_days)
    # Update pool
    _updatePool()
    let (underlying_asset : felt) = asset()
    update_user_after_deposit(receiver, underlying_asset, assets)

    # Update user info
    let (cur_user_info : UserInfo) = userInfo.read(receiver)
    let (new_amount : Uint256) = uint256_checked_add(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=cur_user_info.rewardDebt)
    userInfo.write(receiver, new_user_info)

    ReentrancyGuard_end()
    return (shares)
end

# `lock_time_days` number of days
@external
func depositLP{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, assets : Uint256, receiver : felt, lock_time_days : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    set_new_deposit_unlock_time(receiver, lock_time_days)
    # Update pool
    _updatePool()
    let (caller_address : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()

    let (token_details : WhitelistedToken) = whitelisted_tokens.read(lp_token)

    if token_details.is_NFT == FALSE:
        let (success : felt) = IERC20.transferFrom(lp_token, caller_address, address_this, assets)
        assert success = TRUE
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        let (id_is_zero : felt) = uint256_is_zero(assets)
        with_attr error_message("invalid token id"):
            assert id_is_zero = FALSE
        end
        IERC721.transferFrom(lp_token, caller_address, address_this, assets)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    # Update user info
    let (cur_user_info : UserInfo) = userInfo.read(receiver)
    # convert to ZKP
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        token_details.mint_calculator_address, assets
    )
    let (new_amount : Uint256) = uint256_checked_add(cur_user_info.amount, zkp_quote)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=cur_user_info.rewardDebt)
    userInfo.write(receiver, new_user_info)

    let (shares : Uint256) = previewDepositLP(lp_token, assets, lock_time_days)
    ERC20_mint(receiver, shares)
    update_user_after_deposit(receiver, lp_token, assets)
    DepositLP.emit(caller_address, receiver, lp_token, assets, shares)
    ReentrancyGuard_end()
    return (shares)
end

@external
func mint{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(shares : Uint256, receiver : felt) -> (assets : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    let (assets : Uint256) = ERC4626_mint(shares, receiver)

    let (underlying_asset : felt) = asset()
    let (default_lock_period : felt) = getDefaultLockTime()
    set_new_deposit_unlock_time(receiver, default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)
    ReentrancyGuard_end()
    return (assets)
end

@external
func redeem{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(shares : Uint256, receiver : felt, owner : felt) -> (assets : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()

    assert_not_before_unlock_time(owner)

    # Update pool
    _updatePool()

    let (assets : Uint256) = ERC4626_redeem(shares, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo.read(owner)
    let (acc_token_per_share : Uint256) = accTokenPerShare.read()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.rewardDebt)

    # Update user info
    let (new_amount : Uint256) = uint256_checked_sub_le(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=div)
    userInfo.write(owner, new_user_info)

    # Send rewards
    let (is_positive : felt) = uint256_lt(Uint256(0, 0), pending_rewards)
    if is_positive == TRUE:
        IERC20.mint(zkp_address, receiver, pending_rewards)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    ReentrancyGuard_end()
    return (assets)
end

# lp_token is the LP token address user deposited first and get the xZKP tokens
# shares amount of xZKP tokens user want to redeem
# @external
# func redeemLP{
#     syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
# }(lp_token : felt, shares : Uint256, owner : felt, receiver : felt) -> (amount : Uint256):
#     alloc_locals
#     Pausable_when_not_paused()
#     ReentrancyGuard_start()
#     different_than_underlying(lp_token)
#     only_whitelisted_token(lp_token)
#     assert_not_before_unlock_time(owner)

# # Update pool
#     _updatePool()

# let (caller : felt) = get_caller_address()

# if caller != owner:
#         decrease_allowance_by_amount(owner, caller, shares)
#         tempvar syscall_ptr : felt* = syscall_ptr
#         tempvar range_check_ptr = range_check_ptr
#         tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
#     else:
#         tempvar syscall_ptr : felt* = syscall_ptr
#         tempvar range_check_ptr = range_check_ptr
#         tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
#     end

# local syscall_ptr : felt* = syscall_ptr
#     local pedersen_ptr : HashBuiltin* = pedersen_ptr

# let (address_this : felt) = get_contract_address()
#     let (contract_lp_balance : Uint256) = IERC20.balanceOf(lp_token, address_this)
#     let (enought_token_balance : felt) = uint256_le(shares, contract_lp_balance)

# if enought_token_balance == FALSE:
#         let (amount_to_withdraw : Uint256) = uint256_sub(shares, contract_lp_balance)
#         withdraw_from_investment_strategies(lp_token, amount_to_withdraw)
#         tempvar syscall_ptr : felt* = syscall_ptr
#         tempvar range_check_ptr = range_check_ptr
#         tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
#     else:
#         tempvar syscall_ptr : felt* = syscall_ptr
#         tempvar range_check_ptr = range_check_ptr
#         tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
#     end

# ERC20_burn(owner, shares)

# let (lp_withdraw_amount : Uint256) = calculate_withdraw_lp_amount(owner, lp_token, shares)
#     remove_from_deposit(owner, lp_token, lp_withdraw_amount)

# let (success : felt) = IERC20.transfer(lp_token, receiver, lp_withdraw_amount)
#     assert success = TRUE
#     WithdrawLP.emit(caller, receiver, owner, lp_token, lp_withdraw_amount, shares)
#     ReentrancyGuard_end()
#     return (lp_withdraw_amount)
# end

@external
func withdraw{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()

    assert_not_before_unlock_time(owner)

    # Update pool
    _updatePool()

    let (shares : Uint256) = ERC4626_withdraw(assets, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo.read(owner)
    let (acc_token_per_share : Uint256) = accTokenPerShare.read()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.rewardDebt)

    # Update user info
    let (new_amount : Uint256) = uint256_checked_sub_le(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=div)
    userInfo.write(owner, new_user_info)

    # Send rewards
    let (is_positive : felt) = uint256_lt(Uint256(0, 0), pending_rewards)
    if is_positive == TRUE:
        IERC20.mint(zkp_address, receiver, pending_rewards)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    ReentrancyGuard_end()
    return (shares)
end

@external
func withdrawLP{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)

    # Update pool
    _updatePool()

    let (caller : felt) = get_caller_address()
    let (shares : Uint256) = previewWithdrawLP(lp_token, assets)
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

    local syscall_ptr : felt* = syscall_ptr
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    let (current_xzkp_user_balance) = balanceOf(owner)

    let (output_le : felt) = uint256_le(shares, current_xzkp_user_balance)
    with_attr error_message("invalid xZKP balance"):
        assert output_le = TRUE
    end
    let (user_current_deposit_amount : Uint256) = deposits.read(owner, lp_token)
    let (user_deposit_after_withdraw : Uint256) = uint256_checked_sub_le(
        user_current_deposit_amount, assets
    )
    deposits.write(owner, lp_token, user_deposit_after_withdraw)

    ERC20_burn(owner, shares)
    IERC20.transfer(lp_token, receiver, assets)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo.read(owner)
    # convert to ZKP
    let (token_details : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        token_details.mint_calculator_address, assets
    )
    let (acc_token_per_share : Uint256) = accTokenPerShare.read()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.rewardDebt)

    # Update user info
    let (new_amount : Uint256) = uint256_checked_sub_le(cur_user_info.amount, zkp_quote)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, rewardDebt=div)
    userInfo.write(owner, new_user_info)

    # Send rewards
    let (zkp_address : felt) = asset()
    let (is_positive : felt) = uint256_lt(Uint256(0, 0), pending_rewards)
    if is_positive == TRUE:
        IERC20.mint(zkp_address, receiver, pending_rewards)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    WithdrawLP.emit(caller, receiver, owner, lp_token, assets, shares)
    return (shares)
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    ERC20_transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    assert_not_before_unlock_time(sender)
    ERC20_transferFrom(sender, recipient, amount)
    return (TRUE)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)

    ERC20_approve(spender, amount)
    return (TRUE)
end

# new_lock_time_days number of days
@external
func setDefaultLockTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_lock_time_days : felt
):
    Ownable_only_owner()
    set_default_lock_time(new_lock_time_days)
    return ()
end

@external
func setStakeBoost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_boost_value : felt
):
    Ownable_only_owner()
    assert_not_zero(new_boost_value)
    lp_stake_boost.write(new_boost_value)
    return ()
end

@external
func setFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt):
    Ownable_only_owner()
    set_fee_percent(fee)
    return ()
end

@external
func setHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    window : felt
):
    Ownable_only_owner()
    set_harvest_window(window)
    return ()
end

@external
func setHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_delay : felt
):
    Ownable_only_owner()
    set_harvest_delay(new_delay)
    return ()
end

@external
func setTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_float : felt
):
    Ownable_only_owner()
    set_target_float_percent(new_float)
    return ()
end

@external
func harvest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategies_len : felt, strategies : felt*
):
    Ownable_only_owner()
    harvest_investment(strategies_len, strategies)
    return ()
end

@external
func depositIntoStrategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt, underlying_amount : Uint256
):
    Ownable_only_owner()
    deposit_into_strategy(strategy_address, underlying_amount)
    return ()
end

@external
func withdrawFromStrategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt, underlying_amount : Uint256
):
    Ownable_only_owner()
    withdraw_from_strategy(strategy_address, underlying_amount)
    return ()
end

@external
func trustStrategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt
):
    Ownable_only_owner()
    trust_strategy(strategy_address)
    return ()
end

@external
func distrustStrategy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy_address : felt
):
    Ownable_only_owner()
    distrust_strategy(strategy_address)
    return ()
end

@external
func claimFees{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : Uint256):
    Ownable_only_owner()
    claim_fees(amount)
    return ()
end

@external
func pause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (emergency_breaker_address : felt) = emergency_breaker.read()
    let (owner : felt) = Ownable_get_owner()
    local permissions
    if owner == caller_address:
        permissions = TRUE
    end
    if emergency_breaker_address == caller_address:
        permissions = TRUE  # either owner or emergency breaker have permission to pause the contract
    end
    with_attr error_message("invalid permissions"):
        assert permissions = TRUE
    end
    Pausable_pause()
    return ()
end

@external
func unpause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    Ownable_only_owner()
    Pausable_unpause()
    return ()
end

#
# Internal
#

func only_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    let (res : WhitelistedToken) = whitelisted_tokens.read(address)
    with_attr error_message("token not whitelisted"):
        assert_not_zero(res.mint_calculator_address)
        assert_not_zero(res.bit_mask)
    end
    return ()
end

func different_than_underlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    with_attr error_message("underlying token not allow"):
        let (underlying_asset : felt) = asset()
        assert_not_equal(underlying_asset, address)
    end
    return ()
end

func withdraw_from_investment_strategies{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(lp_token_address : felt, amount : Uint256):
    # TODO: implement
    assert 0 = 1
    return ()
end

# return the first available bit in the mask
func get_next_available_bit_in_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(index : felt, bit_mask : felt) -> (res : felt):
    let (value : felt) = pow(2, index)
    let (and_result : felt) = bitwise_and(value, bit_mask)
    if and_result == 0:
        return (value)
    end

    return get_next_available_bit_in_mask(index + 1, bit_mask)
end

func get_tokens_addresses_from_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(position : felt, bit_mask : felt, tokens_allocation_index : felt, array : felt*) -> (
    length : felt
):
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
            position + 1, bit_mask_left, tokens_allocation_index + 1, array
        )
    end
    return get_tokens_addresses_from_mask(
        position + 1, bit_mask_left, tokens_allocation_index, array
    )
end

func add_token_to_user_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt):
    let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
    let (new_user_tokens_mask : felt) = bitwise_or(
        user_current_tokens_mask, whitelisted_token.bit_mask
    )
    user_staked_tokens.write(user, new_user_tokens_mask)
    return ()
end

func assert_not_before_unlock_time{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(user : felt):
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    with_attr error_message(
            "timestamp {current_block_timestamp} lower than deposit unlock time {unlock_time}"):
        assert_le(unlock_time, current_block_timestamp)
    end
    return ()
end

func calculate_withdraw_lp_amount{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(owner : felt, lp_token : felt, sharesAmount : Uint256) -> (amount : Uint256):
    return (sharesAmount)
end

func set_new_deposit_unlock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, lock_time_days : felt
):
    alloc_locals
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    let (seconds : felt) = days_to_seconds(lock_time_days)
    with_attr error_message("new deadline should be higher or equal to the old deposit"):
        assert_le(unlock_time, current_block_timestamp + seconds)
    end
    deposit_unlock_time.write(user, current_block_timestamp + seconds)
    return ()
end

# update user deposit info and staked tokens bit mask
func update_user_after_deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt, new_amount : Uint256):
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
func remove_from_deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt, withdraw_amount : Uint256):
    alloc_locals
    let (current_user_deposit_amount : Uint256) = deposits.read(user, token)
    let (withdraw_all_tokens : felt) = uint256_lt(current_user_deposit_amount, withdraw_amount)
    if withdraw_all_tokens == TRUE:
        deposits.write(user, token, Uint256(0, 0))
        let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
        let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
        let (new_user_tokens_mask : felt) = bitwise_xor(
            user_current_tokens_mask, whitelisted_token.bit_mask
        )
        user_staked_tokens.write(user, new_user_tokens_mask)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    else:
        let (new_user_deposit_amount : Uint256) = uint256_checked_sub_le(
            current_user_deposit_amount, withdraw_amount
        )
        deposits.write(user, token, new_user_deposit_amount)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end
    return ()
end

#
# Staking Rewards
#

@storage_var
func lastRewardBlock() -> (res : felt):
end

@storage_var
func rewardPerBlock() -> (res : Uint256):
end

@storage_var
func accTokenPerShare() -> (res : Uint256):
end

@storage_var
func endBlock() -> (res : felt):
end

@storage_var
func startBlock() -> (res : felt):
end

@storage_var
func userInfo(user : felt) -> (userInfo : UserInfo):
end

@event
func NewRewardPerBlockAndEndBlock(newRewardPerBlock : Uint256, newEndBlock : felt):
end

@event
func HarvestRewards(user : felt, harvestAmount : Uint256):
end

# @notice Update reward per block and the end block
# @param newRewardPerBlock the new reward per block
# @param newEndBlock the new end block
@external
func updateRewardPerBlockAndEndBlock{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(_reward_per_block : Uint256, new_end_block : felt):
    alloc_locals
    Ownable_only_owner()
    let (local start_block : felt) = startBlock.read()
    let (block_number : felt) = get_block_number()
    let (is_lower : felt) = is_le(start_block, block_number)

    if is_lower == TRUE:
        _updatePool()
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    with_attr error_message("Owner: New endBlock must be after current block"):
        assert_lt(block_number, new_end_block)
    end
    with_attr error_message("Owner: New endBlock must be after start block"):
        assert_lt(start_block, new_end_block)
    end

    endBlock.write(new_end_block)
    rewardPerBlock.write(_reward_per_block)

    NewRewardPerBlockAndEndBlock.emit(
        newRewardPerBlock=_reward_per_block, newEndBlock=new_end_block
    )

    return ()
end

# @notice Harvest pending rewards
@external
func harvestRewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    # Update pool
    _updatePool()
    let (caller : felt) = get_caller_address()
    let (cur_user_info : UserInfo) = userInfo.read(caller)
    let (acc_token_per_share : Uint256) = accTokenPerShare.read()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.rewardDebt)

    let new_user_info : UserInfo = UserInfo(amount=cur_user_info.amount, rewardDebt=div)
    userInfo.write(caller, new_user_info)

    let (zkp_address : felt) = asset()
    IERC20.mint(zkp_address, caller, pending_rewards)

    ReentrancyGuard_end()
    return ()
end

# @notice Update reward variables of the pool to be up-to-date.
func _updatePool{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (block_number : felt) = get_block_number()
    let (last_reward_block : felt) = lastRewardBlock.read()

    with_attr error_message("update pool not possible"):
        assert_lt(last_reward_block, block_number)
    end

    let (staked_supply : Uint256) = totalAssets()

    let (yesno : felt) = uint256_eq(staked_supply, Uint256(0, 0))
    if yesno == TRUE:
        lastRewardBlock.write(block_number)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        return ()
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    let (multiplier : felt) = _getMultiplier(last_reward_block, block_number)
    let (u_multiplier : Uint256) = _felt_to_uint(multiplier)
    let (reward_per_block : Uint256) = rewardPerBlock.read()
    let (token_reward : Uint256) = uint256_checked_mul(u_multiplier, reward_per_block)

    # Update only if token reward for staking is not null
    let (is_positive : felt) = uint256_lt(Uint256(0, 0), token_reward)
    if is_positive == TRUE:
        let PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
        let (precise_token_reward : Uint256) = uint256_checked_mul(token_reward, PRECISION_FACTOR)
        let (divider : Uint256, _) = uint256_checked_div_rem(precise_token_reward, staked_supply)
        let (local cur_acc_token_per_share : Uint256) = accTokenPerShare.read()
        let (_acc_token_per_share : Uint256) = uint256_checked_add(cur_acc_token_per_share, divider)
        accTokenPerShare.write(_acc_token_per_share)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    # Update last reward block only if it wasn't updated after or at the end block
    let (end_block : felt) = endBlock.read()
    let (is_lower : felt) = is_le(last_reward_block, end_block)

    if is_lower == TRUE:
        lastRewardBlock.write(block_number)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    return ()
end

@view
func calculatePendingRewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt
) -> (rewards : Uint256):
    alloc_locals
    # Calcuating pending rewards
    let PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
    let (block_number) = get_block_number()
    let (last_reward_block : felt) = lastRewardBlock.read()
    let (reward_per_block : Uint256) = rewardPerBlock.read()
    let (acc_token_per_share : Uint256) = accTokenPerShare.read()
    let (total_assets : Uint256) = totalAssets()

    let (is_lower_block : felt) = is_le(last_reward_block, block_number - 1)
    let (has_staked_supply : felt) = uint256_is_zero(total_assets)
    let (is_valid : felt) = and(is_lower_block, has_staked_supply)
    if is_valid == TRUE:
        let (multiplier : felt) = _getMultiplier(last_reward_block, block_number)
        let (u_multiplier : Uint256) = _felt_to_uint(multiplier)
        let (tokenReward : Uint256) = uint256_checked_mul(u_multiplier, reward_per_block)
        let (newTokenReward : Uint256) = uint256_checked_mul(tokenReward, PRECISION_FACTOR)
        let (modifiedTokenReward : Uint256, _) = uint256_checked_div_rem(newTokenReward, total_assets)
        let (adjustedTokenPerShare : Uint256) = uint256_checked_add(
            acc_token_per_share, modifiedTokenReward
        )
        let (cur_user_info : UserInfo) = userInfo.read(user)
        let userAmount : Uint256 = cur_user_info.amount
        let userRewardDebt : Uint256 = cur_user_info.rewardDebt
        let (final_pending_amount : Uint256) = uint256_checked_mul(userAmount, adjustedTokenPerShare)
        let (precise_final_pamount : Uint256, _) = uint256_checked_div_rem(
            final_pending_amount, PRECISION_FACTOR
        )
        let (pendingRewards : Uint256) = uint256_checked_sub_le(precise_final_pamount, userRewardDebt)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        return (rewards=pendingRewards)
    else:
        let (cur_user_info : UserInfo) = userInfo.read(user)
        let (acc_token_per_share : Uint256) = accTokenPerShare.read()
        let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, acc_token_per_share)
        let PRECISION_FACTOR = Uint256(10 ** 12, 0)
        let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)
        let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.rewardDebt)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        return (rewards=pending_rewards)
    end
end

# @notice Return reward multiplier over the given "from" to "to" block.
#   @param from block to start calculating reward
#   @param to block to finish calculating reward
#   @return the multiplier for the period
@view
func _getMultiplier{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _from : felt, _to : felt
) -> (multiplier : felt):
    alloc_locals
    let (end_block : felt) = endBlock.read()
    let (is_lower : felt) = is_le(_to, end_block)
    let (is_greater : felt) = is_le(end_block, _from)
    if is_lower == TRUE:
        return (multiplier=_to - _from)
    else:
        if is_greater == TRUE:
            return (multiplier=0)
        else:
            return (multiplier=end_block - _from)
        end
    end
end
