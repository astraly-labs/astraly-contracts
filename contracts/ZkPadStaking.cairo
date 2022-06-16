%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_lt, uint256_check
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

from openzeppelin.access.ownable import (
    Ownable_only_owner,
    Ownable_initializer,
    Ownable_get_owner,
    Ownable_transfer_ownership,
)
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
from contracts.openzeppelin.upgrades.library import Proxy

from contracts.erc4626.ERC4626 import (
    name,
    symbol,
    totalSupply,
    decimals,
    balanceOf,
    allowance,
    asset,
    totalAssets,
    convertToShares,
    convertToAssets,
    maxDeposit,
    maxMint,
    maxWithdraw,
    previewWithdraw,
    maxRedeem,
    previewRedeem,
    ERC4626_withdraw,
    ERC4626_deposit,
    ERC4626_initializer,
    ERC4626_redeem,
    ERC4626_mint,
    ERC4626_previewDeposit,
    ERC4626_previewMint,
    ERC4626_convertToShares,
)
from contracts.erc4626.library import (
    getWithdrawalStack,
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
    harvest_investment,
    deposit_into_strategy,
    withdraw_from_strategy,
    trust_strategy,
    distrust_strategy,
    claim_fees,
    calculate_lock_time_bonus,
    check_enough_underlying_balance,
    can_harvest,
    push_to_withdrawal_stack,
    pop_from_withdrawal_stack,
    set_withdrawal_stack,
    replace_withdrawal_stack_index,
    swap_withdrawal_stack_indexes,
    decrease_allowance_by_amount,
    set_default_lock_time,
    days_to_seconds,
    default_lock_time_days,
)
from contracts.utils import (
    uint256_is_zero,
    uint256_is_not_zero,
    uint256_assert_not_zero,
    and,
    is_lt,
)
from contracts.utils.Uint256_felt_conv import _felt_to_uint
from InterfaceAll import IERC20, UserInfo

@contract_interface
namespace IMintCalculator:
    func getPoolAddress() -> (address : felt):
    end

    func getAmountToMint(input : Uint256) -> (amount : Uint256):
    end
end

struct WhitelistedToken:
    member bit_mask : felt
    member mint_calculator_address : felt
    member is_NFT : felt
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

@event
func NewRewardPerBlockAndEndBlock(newRewardPerBlock : Uint256, newEndBlock : felt):
end

@event
func HarvestRewards(user : felt, harvestAmount : Uint256):
end

#
# Storage variables
#
@storage_var
func last_reward_block() -> (res : felt):
end

@storage_var
func reward_per_block() -> (res : Uint256):
end

@storage_var
func acc_token_per_share() -> (res : Uint256):
end

@storage_var
func end_block() -> (res : felt):
end

@storage_var
func start_block() -> (res : felt):
end

@storage_var
func user_info(user : felt) -> (info : UserInfo):
end

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

@storage_var
func harvest_task_contract() -> (address : felt):
end

#
# View
#

@view
func getUserDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, token : felt
) -> (amount : Uint256):
    let (amount : Uint256) = deposits.read(user, token)
    return (amount)
end

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
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    let (default_lock_period : felt) = getDefaultLockTime()
    let (shares) = ERC4626_previewDeposit(assets, default_lock_period)
    return (shares)
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
    let (shares : Uint256) = ERC4626_previewDeposit(zkp_quote, lock_time)
    let (current_lp_boost : felt) = lp_stake_boost.read()
    if current_lp_boost == 0:
        return (shares)
    end
    let (applied_boost : Uint256) = uint256_checked_mul(shares, Uint256(current_lp_boost, 0))
    let (res : Uint256, _) = uint256_checked_div_rem(applied_boost, Uint256(10, 0))
    return (res)
end

@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (default_lock_period : felt) = default_lock_time_days.read()
    let (assets) = ERC4626_previewMint(shares, default_lock_period)
    return (assets)
end

@view
func previewMintForTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (assets : Uint256):
    let (assets) = ERC4626_previewMint(shares, lock_time)
    return (assets)
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
    let (address) = Proxy.get_implementation()
    return (address)
end

@view
func previewWithdrawLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, input : Uint256
) -> (amount : Uint256):
    only_whitelisted_token(lp_token)
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
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
    let (lock_time_days : felt) = default_lock_time_days.read()
    return (lock_time_days)
end

@view
func getHarvestTaskContract{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    ) -> (address : felt):
    let (address : felt) = harvest_task_contract.read()
    return (address)
end

@view
func canHarvest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    yes_no : felt
):
    let (res : felt) = can_harvest()
    return (res)
end

@view
func rewardPerBlock{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    reward : Uint256
):
    let (reward : Uint256) = reward_per_block.read()
    return (reward)
end

@view
func startBlock{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    block : felt
):
    let (res : felt) = start_block.read()
    return (res)
end

@view
func endBlock{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    block : felt
):
    let (res : felt) = end_block.read()
    return (res)
end

@view
func lastRewardBlock{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    block : felt
):
    let (block : felt) = last_reward_block.read()
    return (block)
end

@view
func accTokenPerShare{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Uint256
):
    let (res : Uint256) = acc_token_per_share.read()
    return (res)
end

@view
func userInfo{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
    info : UserInfo
):
    let (res : UserInfo) = user_info.read(user)
    return (res)
end

@view
func calculatePendingRewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt
) -> (rewards : Uint256):
    alloc_locals
    tempvar PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
    let (staked_token_supply : Uint256) = totalAssets()
    let (block_number : felt) = get_block_number()
    let (current_last_reward_block : felt) = lastRewardBlock()

    let (block_no_higher_than_last_reward : felt) = is_lt(current_last_reward_block, block_number)
    let (staked_token_supply_not_zero : felt) = uint256_is_not_zero(staked_token_supply)
    let (current_acc_token_per_share : Uint256) = accTokenPerShare()
    let (cur_user_info : UserInfo) = userInfo(user)
    let (yes_no : felt) = and(block_no_higher_than_last_reward, staked_token_supply_not_zero)
    if yes_no == TRUE:
        let (multiplier : felt) = getMultiplier(current_last_reward_block, block_number)
        let (current_reward_per_block : Uint256) = rewardPerBlock()
        let (token_reward : Uint256) = uint256_checked_mul(
            Uint256(multiplier, 0), current_reward_per_block
        )

        let (mul : Uint256) = uint256_checked_mul(token_reward, PRECISION_FACTOR)
        let (div : Uint256, _) = uint256_checked_div_rem(mul, staked_token_supply)
        let (adjusted_token_per_share : Uint256) = uint256_checked_add(
            current_acc_token_per_share, div
        )

        let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, adjusted_token_per_share)
        let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)
        let (res : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)

        return (res)
    else:
        let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, current_acc_token_per_share)
        let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)
        let (res : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)
        return (res)
    end
end

# @notice Return reward multiplier over the given "from" to "to" block.
#   @param from block to start calculating reward
#   @param to block to finish calculating reward
#   @return the multiplier for the period
@view
func getMultiplier{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _from : felt, _to : felt
) -> (multiplier : felt):
    alloc_locals
    let (current_end_block : felt) = endBlock()
    let (is_lower : felt) = is_le(_to, current_end_block)
    if is_lower == TRUE:
        return (multiplier=_to - _from)
    end
    let (is_greater : felt) = is_le(current_end_block, _from)

    if is_greater == TRUE:
        return (multiplier=0)
    else:
        return (multiplier=current_end_block - _from)
    end
end

#
# Externals
#

@external
func initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt,
    symbol : felt,
    asset_addr : felt,
    owner : felt,
    _reward_per_block : Uint256,
    start_reward_block : felt,
    end_reward_block : felt,
):
    alloc_locals
    assert_not_zero(owner)
    Proxy.initializer(owner)
    ERC4626_initializer(name, symbol, asset_addr)
    Ownable_initializer(owner)
    setDefaultLockTime(365)
    setStakeBoost(25)
    setFeePercent(1)  # TODO : Check division later

    # # Add ZKP token to the whitelist and bit mask on first position
    token_mask_addresses.write(1, asset_addr)
    whitelisted_tokens_mask.write(1)
    whitelisted_tokens.write(asset_addr, WhitelistedToken(1, 0, FALSE))

    # Initialize Rewards params
    reward_per_block.write(_reward_per_block)
    start_block.write(start_reward_block)
    end_block.write(end_reward_block)
    last_reward_block.write(start_reward_block)
    return ()
end

@external
func upgrade{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_implementation : felt
):
    Proxy.assert_only_admin()
    Proxy._set_implementation(new_implementation)
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
    uint256_assert_not_zero(assets)
    # Update pool
    update_pool()

    let (default_lock_time : felt) = getDefaultLockTime()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, default_lock_time)
    let (underlying_asset : felt) = asset()
    set_new_deposit_unlock_time(receiver, default_lock_time)
    update_user_after_deposit(receiver, underlying_asset, assets)

    # Update user info
    update_user_info_on_deposit(receiver, assets)

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
    uint256_assert_not_zero(assets)
    # Update pool
    update_pool()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, lock_time_days)
    set_new_deposit_unlock_time(receiver, lock_time_days)
    let (underlying_asset : felt) = asset()
    update_user_after_deposit(receiver, underlying_asset, assets)

    update_user_info_on_deposit(receiver, assets)
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
    uint256_assert_not_zero(assets)
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    set_new_deposit_unlock_time(receiver, lock_time_days)
    # Update pool
    update_pool()
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

    # convert to ZKP
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        token_details.mint_calculator_address, assets
    )
    # Update user info
    update_user_info_on_deposit(receiver, zkp_quote)

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
    # Ownable_only_owner()
    uint256_assert_not_zero(shares)
    update_pool()
    let (assets : Uint256) = ERC4626_mint(shares, receiver)

    let (underlying_asset : felt) = asset()
    let (default_lock_period : felt) = getDefaultLockTime()
    set_new_deposit_unlock_time(receiver, default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)
    update_user_info_on_deposit(receiver, assets)
    ReentrancyGuard_end()
    return (assets)
end

@external
func mintForTime{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(shares : Uint256, receiver : felt, lock_time_days : felt) -> (assets : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    # Ownable_only_owner()
    uint256_assert_not_zero(shares)
    update_pool()
    let (assets : Uint256) = ERC4626_mint(shares, receiver)

    # Update user info
    update_user_info_on_deposit(receiver, assets)

    let (underlying_asset : felt) = asset()
    set_new_deposit_unlock_time(receiver, lock_time_days)
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
    let (withdraw_amount : Uint256) = previewRedeem(shares)
    check_enough_underlying_balance(withdraw_amount)
    # Update pool
    update_pool()

    let (assets : Uint256) = ERC4626_redeem(shares, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo(owner)
    let (current_acc_token_per_share : Uint256) = accTokenPerShare()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, current_acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)

    # Update user info
    update_user_info_on_withdraw(receiver, assets)

    # Send rewards
    let (is_positive : felt) = uint256_is_not_zero(pending_rewards)
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

@external
func withdraw{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    assert_not_before_unlock_time(owner)
    check_enough_underlying_balance(assets)
    # Update pool
    update_pool()

    let (shares : Uint256) = ERC4626_withdraw(assets, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo(owner)
    let (current_acc_token_per_share : Uint256) = accTokenPerShare()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, current_acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)

    # Update user info
    update_user_info_on_withdraw(owner, assets)

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
    update_pool()

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
    WithdrawLP.emit(caller, receiver, owner, lp_token, assets, shares)

    # Harvest pending rewards
    let (cur_user_info : UserInfo) = userInfo(owner)
    let (current_acc_token_per_share : Uint256) = accTokenPerShare()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, current_acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)

    # convert to ZKP
    let (token_details : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        token_details.mint_calculator_address, assets
    )
    # Update user info
    update_user_info_on_withdraw(owner, zkp_quote)

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
    alloc_locals
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    update_pool()
    ERC20_transfer(recipient, amount)
    update_user_info_on_withdraw(caller_address, amount)
    update_user_info_on_deposit(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    assert_not_before_unlock_time(sender)
    update_pool()
    ERC20_transferFrom(sender, recipient, amount)
    update_user_info_on_withdraw(sender, amount)
    update_user_info_on_deposit(recipient, amount)
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
func setHarvestTaskContract{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    Ownable_only_owner()
    assert_not_zero(address)
    harvest_task_contract.write(address)
    return ()
end

@external
func harvest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategies_len : felt, strategies : felt*
):
    only_owner_or_harvest_task_contract()
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
func pushToWithdrawalStack{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    strategy : felt
):
    Ownable_only_owner()
    push_to_withdrawal_stack(strategy)
    return ()
end

@external
func popFromWithdrawalStack{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    Ownable_only_owner()
    pop_from_withdrawal_stack()
    return ()
end

@external
func setWithdrawalStack{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    stack_len : felt, stack : felt*
):
    Ownable_only_owner()
    set_withdrawal_stack(stack_len, stack)
    return ()
end

@external
func replaceWithdrawalStackIndex{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    index : felt, address : felt
):
    Ownable_only_owner()
    replace_withdrawal_stack_index(index, address)
    return ()
end

@external
func swapWithdrawalStackIndexes{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    index1 : felt, index2 : felt
):
    Ownable_only_owner()
    swap_withdrawal_stack_indexes(index1, index2)
    return ()
end

#
# Staking Rewards
#

# @notice Update reward per block and the end block
# @param newRewardPerBlock the new reward per block
# @param newEndBlock the new end block
@external
func updateRewardPerBlockAndEndBlock{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(_reward_per_block : Uint256, new_end_block : felt):
    alloc_locals
    Ownable_only_owner()
    let (local current_start_block : felt) = startBlock()
    let (block_number : felt) = get_block_number()
    let (is_lower : felt) = is_le(current_start_block, block_number)

    if is_lower == TRUE:
        update_pool()
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
        assert_lt(current_start_block, new_end_block)
    end

    end_block.write(new_end_block)
    reward_per_block.write(_reward_per_block)

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
    update_pool()
    let (caller : felt) = get_caller_address()
    let (cur_user_info : UserInfo) = userInfo(caller)
    let (current_acc_token_per_share : Uint256) = accTokenPerShare()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, current_acc_token_per_share)
    let PRECISION_FACTOR = Uint256(10 ** 12, 0)
    let (div : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (pending_rewards : Uint256) = uint256_checked_sub_le(div, cur_user_info.reward_debt)

    let (rewards_not_zero : felt) = uint256_is_not_zero(pending_rewards)

    with_attr error_message("Harvest: Pending rewards must be > 0"):
        assert rewards_not_zero = TRUE
    end

    let new_user_info : UserInfo = UserInfo(amount=cur_user_info.amount, reward_debt=div)
    user_info.write(caller, new_user_info)

    let (zkp_address : felt) = asset()
    IERC20.mint(zkp_address, caller, pending_rewards)

    HarvestRewards.emit(caller, pending_rewards)
    ReentrancyGuard_end()
    return ()
end

@external
func transferOwnership{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_owner : felt
):
    assert_not_zero(new_owner)
    Ownable_transfer_ownership(new_owner)
    return ()
end

@external
func pause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (owner : felt) = Ownable_get_owner()
    local permissions
    if owner == caller_address:
        permissions = TRUE
    end
    let (emergency_breaker_address : felt) = emergency_breaker.read()
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

func only_owner_or_harvest_task_contract{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}():
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (owner : felt) = Ownable_get_owner()
    local permissions
    if owner == caller_address:
        permissions = TRUE
    end
    let (harvest_task_contract_address : felt) = harvest_task_contract.read()
    if harvest_task_contract_address == caller_address:
        permissions = TRUE
    end
    with_attr error_message("Ownable: caller is not the owner or harvest task contract"):
        assert permissions = TRUE
    end

    return ()
end

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
        return ()
    end
    return ()
end

# remove user staked tokens from the bit mask if new balance is 0
func remove_from_deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt, withdrawned_amount : Uint256):
    alloc_locals
    let (current_user_deposit_amount : Uint256) = deposits.read(user, token)
    let (withdraw_all : felt) = uint256_le(current_user_deposit_amount, withdrawned_amount)  # can withdraw more than
    if withdraw_all == TRUE:
        deposits.write(user, token, Uint256(0, 0))
        let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
        let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
        let (new_user_tokens_mask : felt) = bitwise_xor(
            user_current_tokens_mask, whitelisted_token.bit_mask
        )
        user_staked_tokens.write(user, new_user_tokens_mask)
        return ()
    else:
        let (new_user_deposit_amount : Uint256) = uint256_checked_sub_lt(
            current_user_deposit_amount, withdrawned_amount
        )
        deposits.write(user, token, new_user_deposit_amount)
        return ()
    end
end

# @notice Update reward variables of the pool to be up-to-date.
func update_pool{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (block_number : felt) = get_block_number()
    let (current_last_reward_block : felt) = lastRewardBlock()
    let (is_lower_or_eq : felt) = is_le(block_number, current_last_reward_block)

    if is_lower_or_eq == TRUE:
        return ()
    end

    let (staked_supply : Uint256) = totalAssets()

    let (yesno : felt) = uint256_is_zero(staked_supply)
    if yesno == TRUE:
        last_reward_block.write(block_number)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        return ()
    end

    let (multiplier : felt) = getMultiplier(current_last_reward_block, block_number)
    let (u_multiplier : Uint256) = _felt_to_uint(multiplier)
    let (current_reward_per_block : Uint256) = rewardPerBlock()
    let (token_reward : Uint256) = uint256_checked_mul(u_multiplier, current_reward_per_block)

    # Update only if token reward for staking is not null
    let (is_positive : felt) = uint256_is_not_zero(token_reward)
    if is_positive == TRUE:
        let PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
        let (cur_acc_token_per_share : Uint256) = accTokenPerShare()

        let (precise_token_reward : Uint256) = uint256_checked_mul(token_reward, PRECISION_FACTOR)
        let (divider : Uint256, _) = uint256_checked_div_rem(precise_token_reward, staked_supply)
        let (new_acc_token_per_share : Uint256) = uint256_checked_add(
            cur_acc_token_per_share, divider
        )
        acc_token_per_share.write(new_acc_token_per_share)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    # Update last reward block only if it wasn't updated after or at the end block
    let (current_end_block : felt) = endBlock()
    let (is_lower : felt) = is_le(current_last_reward_block, current_end_block)

    if is_lower == TRUE:
        last_reward_block.write(block_number)
        return ()
    end

    return ()
end

func update_user_info_on_deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, assets : Uint256
):
    alloc_locals
    let (cur_user_info : UserInfo) = userInfo(user)
    # let PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
    # let (cur_acc_token_per_share : Uint256) = accTokenPerShare()
    # let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, cur_acc_token_per_share)
    # let (new_reward_debt : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (new_amount : Uint256) = uint256_checked_add(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(
        amount=new_amount, reward_debt=cur_user_info.reward_debt
    )
    user_info.write(user, new_user_info)
    return ()
end

func update_user_info_on_withdraw{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(user : felt, assets : Uint256):
    alloc_locals
    let (cur_user_info : UserInfo) = userInfo(user)
    let PRECISION_FACTOR : Uint256 = Uint256(10 ** 12, 0)
    let (cur_acc_token_per_share : Uint256) = accTokenPerShare()
    let (mul : Uint256) = uint256_checked_mul(cur_user_info.amount, cur_acc_token_per_share)
    let (new_reward_debt : Uint256, _) = uint256_checked_div_rem(mul, PRECISION_FACTOR)

    let (new_amount : Uint256) = uint256_checked_sub_le(cur_user_info.amount, assets)
    let new_user_info : UserInfo = UserInfo(amount=new_amount, reward_debt=new_reward_debt)
    user_info.write(user, new_user_info)
    return ()
end
