%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

from contracts.Referral.library import Referral
from contracts.AstralyAccessControl import AstralyAccessControl

const IDO_ROLE = 'IDO_CONTRACT';

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt, refferal_cut: Uint256
) {
    AstralyAccessControl.initializer(admin_address);
    Referral.set_referral_cut(refferal_cut);
    return ();
}

@view
func get_referrer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (
    res: felt
) {
    let (res) = Referral.get_referrer(user);
    return (res,);
}

@view
func get_referral_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt
) -> (res: felt) {
    let (res) = Referral.get_referral_count(user);
    return (res,);
}

@view
func get_referral_cut{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Uint256
) {
    let (res) = Referral.get_referral_cut();
    return (res,);
}

@view
func get_referral_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    performance_fees: Uint256
) -> (res: Uint256) {
    let (res) = Referral.get_referral_fees(performance_fees);
    return (res,);
}

@external
func record_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt, referrer: felt
) {
    AstralyAccessControl.assert_only_owner();
    Referral.record_referral(user, referrer);
    return ();
}

@external
func set_referral_cut{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    cut: Uint256
) {
    AstralyAccessControl.assert_only_owner();
    Referral.set_referral_cut(cut);
    return ();
}

@external
func transfer_ownership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_owner: felt
) {
    AstralyAccessControl.transfer_ownership(new_owner);
    return ();
}
