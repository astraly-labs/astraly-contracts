%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero

from contracts.AstralyINOContract import (
    sale_created,
    registration_time_set,
    set_purchase_round_params,
    set_registration_time,
    set_sale_params,
    participate,
    users_registrations,
    users_registrations_len,
    UserRegistrationDetails,
    getWinners,
    constructor,
    get_registration,
    get_current_sale,
    registerUser,
    _register_user,
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

    _register_user(users[index], registration, score_arr[index]);

    return register_users_rec(arr_len, index + 1, users, score_arr, registration);
}
