%lang starknet

from contracts.IDO.ido_library import Sale
from contracts.IDO.ido_library import Participation
from starkware.cairo.common.uint256 import Uint256
from contracts.IDO.ido_library import PurchaseRound
from contracts.IDO.ido_library import Registration

@contract_interface
namespace IAstralyinocontract {
    func get_ido_launch_date() -> (res: felt) {
    }

    func get_current_sale() -> (res: Sale) {
    }

    func get_user_info(account: felt) -> (
        participation: Participation,
        allocations: Uint256,
        is_registered: felt,
        has_participated: felt,
    ) {
    }

    func get_purchase_round() -> (res: PurchaseRound) {
    }

    func get_registration() -> (res: Registration) {
    }

    func get_allocation(address: felt) -> (res: Uint256) {
    }

    func set_sale_params(
        _token_address: felt,
        _sale_owner_address: felt,
        _token_price: Uint256,
        _amount_of_tokens_to_sell: Uint256,
        _sale_end_time: felt,
        _tokens_unlock_time: felt,
    ) {
    }

    func set_sale_token(_sale_token_address: felt) {
    }

    func set_registration_time(_registration_time_starts: felt, _registration_time_ends: felt) {
    }

    func set_purchase_round_params(
        _purchase_time_starts: felt, _purchase_time_ends: felt, max_participation: Uint256
    ) {
    }

    func register_user(signature_len: felt, signature: felt*, signature_expiration: felt) {
    }

    func participate(amount_paid: Uint256) {
    }

    func withdraw_from_contract() {
    }

    func withdraw_leftovers() {
    }

    func withdraw_tokens(portion_id: felt) {
    }
}
