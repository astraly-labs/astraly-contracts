# SPDX-License-Identifier: MIT
%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.starknet.common.syscalls import get_block_number, get_block_timestamp
from starkware.cairo.common.math import assert_lt, assert_not_zero, assert_le
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_sub,
    uint256_le,
    uint256_lt,
    uint256_check,
    uint256_eq,
    uint256_neg,
    uint256_signed_nn,
)
from starkware.cairo.common.bool import TRUE

from InterfaceAll import IERC20
from openzeppelin.access.ownable import Ownable_only_owner, Ownable_initializer
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_lt,
    uint256_checked_mul,
    uint256_checked_div_rem,
    uint256_checked_sub_le,
)
from contracts.utils.Uint256_felt_conv import _uint_to_felt, _felt_to_uint

@event
func Released(payee : felt, amount : Uint256):
end

@event
func PayeeAdded(payee : felt):
end

@storage_var
func payees(i : felt) -> (payee : felt):
end

@storage_var
func token() -> (token_address : felt):
end

@storage_var
func duration_in_seconds() -> (duration_in_seconds : felt):
end

@storage_var
func start_timestamp() -> (start_timestamp : felt):
end

@storage_var
func released(payee : felt) -> (released : Uint256):
end

@storage_var
func shares(payee : felt) -> (shares : Uint256):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    payees_len : felt,
    payees : felt*,
    shares_len : felt,
    shares : Uint256*,
    _start_timestamp : felt,
    duration_seconds : felt,
    token_address : felt,
):
    alloc_locals
    let (caller) = get_caller_address()
    Ownable_initializer(caller)

    local array_index = 0
    _populate_arrays(payees_len, payees, shares, array_index)

    assert_not_zero(_start_timestamp)
    assert_not_zero(duration_seconds)

    start_timestamp.write(_start_timestamp)
    duration_in_seconds.write(duration_seconds)
    token.write(token_address)

    return ()
end

@external
func release{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (_timestamp) = get_block_timestamp()
    let (caller) = get_caller_address()
    let (user_shares) = shares.read(caller)

    let (has_shares) = uint256_le(user_shares, Uint256(0, 0))
    with_attr error_message("ZkPadVesting::User has no shares"):
        assert_not_zero(1 - has_shares)
    end

    let (this_address) = get_contract_address()
    let (user_released) = released.read(caller)
    let (timestamp_uint : Uint256) = _felt_to_uint(_timestamp)
    let (releasable : Uint256) = vested_amount(caller, timestamp_uint)

    let (updated_releasable : Uint256) = uint256_checked_sub_le(releasable, user_released)

    # Update released balance
    released.write(caller, updated_releasable)
    # Emit Released Event
    Released.emit(caller, updated_releasable)

    # Transfer tokens to payee
    let (token_address) = token.read()
    let (success : felt) = IERC20.transfer(
        contract_address=token_address, recipient=caller, amount=updated_releasable
    )
    with_attr error_message("ZkPadVesting::Transfer failed"):
        assert success = TRUE
    end

    return ()
end

@view
func vested_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, timestamp : Uint256
) -> (amount : Uint256):
    alloc_locals
    let (this_address) = get_contract_address()
    let (token_address) = token.read()

    let (_released : Uint256) = released.read(user)
    let (balance : Uint256) = IERC20.balanceOf(contract_address=token_address, account=this_address)

    let (sum) = uint256_checked_add(_released, balance)
    let (_amount) = _vesting_schedule(sum, timestamp)

    return (_amount)
end

@view
func _vesting_schedule{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    total_allocation : Uint256, timestamp : Uint256
) -> (amount : Uint256):
    alloc_locals
    let (start) = start_timestamp.read()
    let (start_uint) = _felt_to_uint(start)

    let (lower_start) = uint256_lt(timestamp, start_uint)
    if lower_start == 1:
        let zero = Uint256(0, 0)
        return (zero)
    else:
        let (duration) = duration_in_seconds.read()
        let (duration_uint) = _felt_to_uint(duration)
        let (end_time) = uint256_checked_add(start_uint, duration_uint)
        let (lower_end) = uint256_lt(end_time, timestamp)
        if lower_end == 1:
            return (total_allocation)
        else:
            let (elapsed : Uint256) = uint256_checked_sub_lt(timestamp, start_uint)
            let (num : Uint256) = uint256_checked_mul(elapsed, total_allocation)
            let (result : Uint256, _) = uint256_checked_div_rem(num, duration_uint)
            return (result)
        end
    end
end

func _populate_arrays{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    len : felt, _payees : felt*, _shares : Uint256*, index : felt
):
    if len == 0:
        return ()
    end

    with_attr error_message("ZkPadVesting::payee can't be null"):
        assert_not_zero(_payees[index])
    end

    payees.write(index, _payees[index])
    shares.write(_payees[index], _shares[index])
    _populate_arrays(len=len - 1, _payees=_payees + 1, _shares=_shares + 1, index=index + 1)
    return ()
end
