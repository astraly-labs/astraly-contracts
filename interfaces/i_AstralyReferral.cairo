%lang starknet

@contract_interface
namespace IAstralyreferral {
    func get_referrers(user: felt) -> (referrers_len: felt, referrers: felt*) {
    }

    func is_referred(user: felt, referrer: felt) -> (res: felt) {
    }

    func record_referral(user: felt, referrer: felt) {
    }

    func set_referral_bonus(bonus: felt) {
    }
}
