%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_lt_felt
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_block_timestamp

from contracts.IDO.ido_library import IDO, UserRegistrationDetails, IDO_winners_arr_len, IDO_winners_arr

from contracts.IDO.AstralyIDOContract import (
    set_purchase_round_params,
    set_registration_time,
    set_sale_params,
    set_vesting_params,
    deposit_tokens,
    participate,
    constructor,
    get_registration,
    get_current_sale,
    get_allocation,
    register_user,
    is_winner,
    Registration,
)

@external
func register_users{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    users_len: felt, users: felt*, score_arr_len: felt, score_arr: felt*
) {
    let (registration: Registration) = get_registration();
    register_users_rec(users_len, 0, users, score_arr, registration);
    return ();
}

func register_users_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    arr_len: felt, index: felt, users: felt*, score_arr: felt*, registration: Registration
) {
    if (arr_len == index) {
        return ();
    }

    IDO._register_user(users[index], registration, score_arr[index]);

    return register_users_rec(arr_len, index + 1, users, score_arr, registration);
}

@view
func getWinners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    arr_len: felt, arr: felt*
) {
    alloc_locals;

    with_attr error_message("AstralyINOContract::getWinners Registration window not closed") {
        let (the_reg) = get_registration();
        let (block_timestamp) = get_block_timestamp();
        assert_lt_felt(the_reg.registration_time_ends, block_timestamp);
    }

    let (arr_len: felt) = IDO_winners_arr_len.read();
    let (arr: felt*) = alloc();

    get_winners_array_rec(arr_len, arr, 0);

    return (arr_len, arr);
}

func get_winners_array_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: felt*, index: felt
) {
    if (index == array_len) {
        return ();
    }
    let (winner_details: UserRegistrationDetails) = IDO_winners_arr.read(index);
    assert array[index] = winner_details.address;

    return get_winners_array_rec(array_len, array, index + 1);
}
