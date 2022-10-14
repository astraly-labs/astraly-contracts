%lang starknet

from starkware.cairo.common.uint256 import Uint256
from contracts.IDO.ido_library import Sale
from contracts.IDO.ido_library import Participation
from contracts.IDO.ido_library import PurchaseRound
from contracts.IDO.ido_library import Registration

@contract_interface
namespace IAstralyidocontract {
    func get_ido_launch_date() -> (res: felt) {
    }

    func get_performance_fee() -> (res: Uint256) {
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

    func get_vesting_portion_percent(portion_id: felt) -> (res: Uint256) {
    }

    func get_vestion_portion_unlock_time(portion_id: felt) -> (res: felt) {
    }

    func get_number_of_vesting_portions() -> (res: felt) {
    }

    func set_vesting_params(
        _unlocking_times_len: felt,
        _unlocking_times: felt*,
        _percents_len: felt,
        _percents: Uint256*,
    ) {
    }

    func set_sale_params(
        _token_address: felt,
        _sale_owner_address: felt,
        _token_price: Uint256,
        _amount_of_tokens_to_sell: Uint256,
        _sale_end_time: felt,
        _tokens_unlock_time: felt,
        _portion_vesting_precision: Uint256,
        _base_allocation: Uint256,
    ) {
    }

    func set_sale_token(_sale_token_address: felt) {
    }

    func set_amm_wrapper(_amm_wrapper_address: felt) {
    }

    func set_performance_fee(_performance_fee: Uint256) {
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

    func deposit_tokens() {
    }

    func withdraw_tokens(portion_id: felt) {
    }

    func withdraw_from_contract() {
    }

    func withdraw_leftovers() {
    }

    func withdraw_multiple_portions(portion_ids_len: felt, portion_ids: felt*) {
    }
}
