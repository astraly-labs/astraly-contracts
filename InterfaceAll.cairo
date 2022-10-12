//###################################################################################
// SPDX-License-Identifier: MIT
// @title InterfaceAll contract
// @dev put all interfaces here
// Interfaces include
// - IZkIDOContract
// - IERC4626
// - ITask
// - IZkIDOFactory
// @author astraly
//###################################################################################

%lang starknet
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.introspection.erc165.IERC165 import IERC165

struct UserInfo {
    amount: Uint256,
    reward_debt: Uint256,
}

struct Purchase_Round {
    time_starts: felt,
    time_ends: felt,
    number_of_purchases: Uint256,
}

struct Registration {
    registration_time_starts: felt,
    registration_time_ends: felt,
    number_of_registrants: Uint256,
}

@contract_interface
namespace IAstralyIDOContract {
    func get_ido_launch_date() -> (res: felt) {
    }

    func register_user(amount: Uint256, account: felt, nb_quest: felt) -> (res: felt) {
    }

    func get_purchase_round() -> (res: Purchase_Round) {
    }

    func get_registration() -> (res: Registration) {
    }

    func calculate_allocation() {
    }
}

@contract_interface
namespace IAccount {
    func isValidSignature(hash: felt, signature_len: felt, signature: felt*) -> (is_valid: felt) {
    }
}

@contract_interface
namespace IAstralyIDOFactory {
    func get_ido_launch_date(id: felt) -> (res: felt) {
    }

    func get_ido_address(id: felt) -> (res: felt) {
    }

    func set_sale_owner_and_token(sale_owner_address: felt, sale_token_address: felt) {
    }

    func is_sale_created_through_factory(sale_address: felt) -> (res: felt) {
    }

    func get_lottery_ticket_contract_address() -> (lottery_ticket_address: felt) {
    }

    func get_random_number_generator_address() -> (random_number_generator_address: felt) {
    }

    func get_payment_token_address() -> (payment_token_address: felt) {
    }

    func get_merkle_root(id: felt) -> (merkle_root: felt) {
    }

    func create_ido(ido_admin: felt) -> (new_ido_contract_address: felt) {
    }

    func get_ido_contract_class_hash() -> (class_hash: felt) {
    }

    func set_ido_contract_class_hash(new_class_hash: felt) {
    }
}

const XOROSHIRO_ADDR = 0x0236b6c5722c5b5e78c215d72306f642de0424a6b56f699d43c98683bea7460d;

@contract_interface
namespace IXoroshiro {
    func next() -> (rnd: felt) {
    }

    func update_seed(seed: felt) {
    }
}

@contract_interface
namespace IERC721 {
    func balanceOf(owner: felt) -> (balance: Uint256) {
    }

    func ownerOf(tokenId: Uint256) -> (owner: felt) {
    }

    func safeTransferFrom(from_: felt, to: felt, tokenId: Uint256, data_len: felt, data: felt*) {
    }

    func transferFrom(from_: felt, to: felt, tokenId: Uint256) {
    }

    func approve(approved: felt, tokenId: Uint256) {
    }

    func setApprovalForAll(operator: felt, approved: felt) {
    }

    func getApproved(tokenId: Uint256) -> (approved: felt) {
    }

    func isApprovedForAll(owner: felt, operator: felt) -> (isApproved: felt) {
    }

    func mint(to: felt, amount: Uint256) {
    }
}
