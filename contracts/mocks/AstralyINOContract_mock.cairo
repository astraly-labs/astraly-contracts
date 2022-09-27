%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero

from contracts.AstralyINOContract import (
    draw_winning_tickets,
    sale_created,
    registration_time_set,
    set_purchase_round_params,
    set_registration_time,
    purchase_round_time_set,
    participate,
    users_registrations,
    users_registrations_len,
    UserRegistrationDetails,
    constructor,
)

@external
func set_user_registration_mock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: UserRegistrationDetails*
) {
    assert_not_zero(array_len);
    write_rec(array_len - 1, array);

    users_registrations_len.write(array_len);
    return ();
}

func write_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt, array: UserRegistrationDetails*
) {
    users_registrations.write(index, array[index]);
    if (index == 0) {
        return ();
    }

    return write_rec(index - 1, array);
}
