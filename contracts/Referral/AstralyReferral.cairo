%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.Referral.library import Referral

@view
func get_referrers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (
    referrers_len: felt, referrers: felt*
) {
    let (referrers_len, referrers) = Referral.get_referrers(user);
    return (referrers_len, referrers);
}

@view
func is_referred{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt, referrer: felt
) -> (res: felt) {
    let (res) = Referral.is_referred(user, referrer);
    return (res,);
}

@external
func record_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt, referrer: felt
) {
    Referral.record_referral(user, referrer);
    return ();
}

@external
func set_referral_bonus{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    bonus: felt
) {
    Referral.set_score_bonus(bonus);
    return ();
}
