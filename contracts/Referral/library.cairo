%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.bool import TRUE
from starkware.cairo.common.alloc import alloc

@storage_var
func Referral_is_referred(user: felt, referrer: felt) -> (res: felt) {
}

@storage_var
func Referral_refferals(user: felt, index: felt) -> (res: felt) {
}

@storage_var
func Referral_refferals_len(user: felt) -> (res: felt) {
}

@storage_var
func Referral_score_bonus() -> (res: felt) {
}

namespace Referral {
    func record_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt, referrer: felt
    ) {
        Referral_is_referred.write(user, referrer, TRUE);
        let (len) = Referral_refferals_len.read(user);
        Referral_refferals.write(user, len, referrer);
        Referral_refferals_len.write(user, len + 1);
        return ();
    }

    func get_referrers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt
    ) -> (arr_len: felt, arr: felt*) {
        alloc_locals;
        let (arr_len: felt) = Referral_refferals_len.read(user);
        let (arr: felt*) = alloc();

        internal.get_referrers_rec(arr_len, arr, 0, user);
        return (arr_len, arr);
    }

    func is_referred{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        user: felt, referrer: felt
    ) -> (res: felt) {
        let (res) = Referral_is_referred.read(user, referrer);
        return (res,);
    }

    func set_score_bonus{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        bonus: felt
    ) {
        Referral_score_bonus.write(bonus);
        return ();
    }
}

namespace internal {
    func get_referrers_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        array_len: felt, array: felt*, index: felt, user: felt
    ) {
        if (index == array_len) {
            return ();
        }
        let (referral) = Referral_refferals.read(user, index);
        assert array[index] = referral;

        return get_referrers_rec(array_len, array, index + 1, user);
    }
}
