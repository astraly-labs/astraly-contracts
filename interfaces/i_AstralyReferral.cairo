%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IAstralyreferral {
    func get_referrer(user: felt) -> (res: felt) {
    }

    func get_referral_count(user: felt) -> (res: felt) {
    }

    func get_referral_cut() -> (res: Uint256) {
    }

    func get_referral_fees(performance_fees: Uint256) -> (res: Uint256) {
    }

    func record_referral(user: felt, referrer: felt) {
    }

    func set_referral_cut(cut: Uint256) {
    }
}
