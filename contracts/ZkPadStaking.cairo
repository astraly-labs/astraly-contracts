%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_check
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp

from contracts.token.ERC20_base import (
    ERC20_name, ERC20_symbol, ERC20_totalSupply, ERC20_decimals, ERC20_balanceOf, ERC20_allowance,
    ERC20_initializer, ERC20_approve, ERC20_increaseAllowance, ERC20_decreaseAllowance,
    ERC20_transfer, ERC20_transferFrom, ERC20_mint)

from contracts.Ownable_base import Ownable_initializer, Ownable_only_owner

from contracts.utils.constants import TRUE

const MAX_TIME = 2 ** 48 - 1

struct User:
    member stake_time : felt
    member unlock_time : felt
    member lock_time : felt
    member staked_amount : felt
    member accumulated_rewards : felt
end

# A mapping from an address to a user
@storage_var
func user_map(address : felt) -> (res : User):
end

@storage_var
func token_total_staked() -> (tokenTotalStaked : felt):
end

@storage_var
func staking_token() -> (stakingToken : felt):
end

@storage_var
func reward_token() -> (rewardToken : felt):
end

@storage_var
func lock_time_period_min() -> (lockTimePeriodMin : felt):
end

@storage_var
func lock_time_period_max() -> (lockTimePeriodMax : felt):
end

@storage_var
func stake_reward_end_time() -> (stakeRewardEndTime : felt):
end

@storage_var
func stake_reward_factor() -> (stakeRewardFactor : felt):
end

@event
func Stake(wallet : felt, amount : felt, date : felt):
end

@event
func Withdraw(wallet : felt, amount : felt, date : felt):
end

@event
func Claimed(wallet : felt, rewardToken : felt, amount : felt):
end

@event
func RewardTokenChanged(oldRewardToken : felt, returnedAmount : felt, newRewardToken : felt):
end

@event
func LockTimePeriodMinChanged(lockTimePeriodMin : felt):
end

@event
func LockTimePeriodMaxChanged(lockTimePeriodMax : felt):
end

@event
func StakeRewardFactorChanged(stakeRewardFactor : felt):
end

@event
func StakeRewardEndTimeChanged(stakeRewardEndTime : felt):
end

@event
func RewardsBurned(staker : felt):
end

@event
func ERC20TokensRemoved(tokenAddress : felt, receiver : felt, amount : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _staking_token : felt, _lock_time_period_min : felt, _lock_time_period_max : felt,
        owner : felt):
    # Initliaze storage variables
    assert_not_zero(_staking_token)
    assert_not_zero(_lock_time_period_min)
    assert_nn_le(_lock_time_period_min, _lock_time_period_max)
    staking_token.write(_staking_token)
    lock_time_period_min.write(_lock_time_period_min)
    lock_time_period_max.write(_lock_time_period_max)
    # Set default values
    stake_reward_factor.write(1000 * 86400)  # Stake 1000 tokens for 1 day to get 1 reward token
    let (block_timestamp) = get_block_timestamp()
    stake_reward_end_time.write(block_timestamp + 365 * 86400)  # Rewards distribution end in 1 year

    Ownable_initializer(owner)
    return ()
end
