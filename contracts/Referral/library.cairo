%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.bool import TRUE
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.security.safemath.library import SafeUint256

@storage_var
func Referral_referrer(user: felt) -> (res: felt) {
}

@storage_var
func Referral_referral_cut() -> (res: Uint256) {
}

@storage_var
func Referral_referrals_count(user: felt) -> (res: felt) {
}

namespace Referral {
    func record_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt, referrer: felt
    ) {
        Referral_referrer.write(user, referrer);
        let (count) = Referral_referrals_count.read(referrer);
        Referral_referrals_count.write(referrer, count + 1);
        return ();
    }

    func get_referrer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt
    ) -> (res: felt) {
        let (res) = Referral_referrer.read(user);
        return (res,);
    }

    func get_referral_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt
    ) -> (res: felt) {
        let (res) = Referral_referrals_count.read(user);
        return (res,);
    }

    func set_referral_cut{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        cut: Uint256
    ) {
        Referral_referral_cut.write(cut);
        return ();
    }

    func get_referral_cut{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: Uint256
    ) {
        let (res) = Referral_referral_cut.read();
        return (res,);
    }

    func get_referral_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        performance_fees: Uint256
    ) -> (res: Uint256) {
        let (cut) = Referral_referral_cut.read();
        let (fees, _) = SafeUint256.div_rem(performance_fees, cut);
        return (res=fees);
    }
}
