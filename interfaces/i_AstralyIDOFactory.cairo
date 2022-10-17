%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IAstralyidofactory {
    func get_ido_address(id: felt) -> (address: felt) {
    }

    func get_ino_address(id: felt) -> (address: felt) {
    }

    func get_random_number_generator_address() -> (res: felt) {
    }

    func get_payment_token_address() -> (payment_token_address: felt) {
    }

    func get_merkle_root(id: felt) -> (merkle_root: felt) {
    }

    func get_ido_contract_class_hash() -> (class_hash: felt) {
    }

    func get_ino_contract_class_hash() -> (class_hash: felt) {
    }

    func grant_owner_role(address: felt) {
    }

    func create_ido(ido_admin: felt, scorer: felt, admin_cut: Uint256) -> (
        new_ido_contract_address: felt
    ) {
    }

    func create_ino(ido_admin: felt, scorer: felt, admin_cut: Uint256) -> (
        new_ino_contract_address: felt
    ) {
    }

    func set_random_number_generator_address(rnd_nbr_gen_adr: felt) {
    }

    func set_payment_token_address(_pmt_tkn_addr: felt) {
    }

    func set_merkle_root(_merkle_root: felt, _id: felt) {
    }

    func set_ido_contract_class_hash(new_class_hash: felt) {
    }

    func set_ino_contract_class_hash(new_class_hash: felt) {
    }
}
