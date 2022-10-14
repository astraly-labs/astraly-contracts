%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_lt_felt, assert_not_zero
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import Uint256, uint256_lt, uint256_eq
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.AstralyAccessControl import AstralyAccessControl
from openzeppelin.security.safemath.library import SafeUint256

from contracts.IDO.ido_library import (
    IDO,
    Sale,
    Participation,
    PurchaseRound,
    Registration,
    TokensWithdrawn,
)
from contracts.utils.Uint256_felt_conv import _uint_to_felt, _felt_to_uint
from contracts.utils import is_lt
from interfaces.i_ERC721 import IERC721

const SALE_OWNER_ROLE = 'SALE_OWNER';

@storage_var
func current_id() -> (res: Uint256) {
}

@event
func INOCreated(new_ino_contract_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt, admin_cut: Uint256
) {
    AstralyAccessControl.initializer(admin_address);
    IDO.initializer(admin_address, admin_cut);

    let (address_this: felt) = get_contract_address();
    INOCreated.emit(address_this);
    return ();
}

//############################################
// #                 GETTERS                 ##
//############################################

@view
func get_ido_launch_date{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: felt
) {
    return IDO.get_ido_launch_date();
}

@view
func get_current_sale{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Sale
) {
    return IDO.get_current_sale();
}

@view
func get_user_info{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account: felt
) -> (
    participation: Participation, allocations: Uint256, is_registered: felt, has_participated: felt
) {
    return IDO.get_user_info(account);
}

@view
func get_purchase_round{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: PurchaseRound
) {
    return IDO.get_purchase_round();
}

@view
func get_registration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Registration
) {
    return IDO.get_registration();
}

@view
func get_allocation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt
) -> (res: Uint256) {
    let count: felt = IDO.get_allocation(address);
    let (ucount) = _felt_to_uint(count);
    return (res=ucount);
}

//############################################
// #                 EXTERNALS               ##
//############################################
@external
func set_sale_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token_address: felt,
    _sale_owner_address: felt,
    _token_price: Uint256,
    _amount_of_tokens_to_sell: Uint256,
    _sale_end_time: felt,
    _tokens_unlock_time: felt,
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_sale_params(
        _token_address,
        _sale_owner_address,
        _token_price,
        _amount_of_tokens_to_sell,
        _sale_end_time,
        _tokens_unlock_time,
    );
    let (winners_max_len: felt) = _uint_to_felt(_amount_of_tokens_to_sell);
    IDO.set_max_winners_len(winners_max_len);
    AstralyAccessControl.grant_role(SALE_OWNER_ROLE, _sale_owner_address);
    return ();
}

@external
func set_sale_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _sale_token_address: felt
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_sale_token(_sale_token_address);
    return ();
}

@external
func set_registration_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _registration_time_starts: felt, _registration_time_ends: felt
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_registration_time(_registration_time_starts, _registration_time_ends);
    return ();
}

@external
func set_purchase_round_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _purchase_time_starts: felt, _purchase_time_ends: felt, max_participation: Uint256
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_purchase_round_params(_purchase_time_starts, _purchase_time_ends, max_participation);
    return ();
}

@external
func register_user{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(signature_len: felt, signature: felt*, signature_expiration: felt) {
    IDO.register_user(signature_len, signature, signature_expiration);
    return ();
}

@external
func participate{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(amount_paid: Uint256) {
    alloc_locals;
    let (account: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (allocation) = get_allocation(account);
    let pmt_token_addr = IDO.get_pmt_token_addr();
    with_attr error_message("participate::Payment token address not set") {
        assert_not_zero(pmt_token_addr);
    }

    let (the_sale: Sale) = get_current_sale();
    let (number_of_tokens_buying, _) = SafeUint256.div_rem(amount_paid, the_sale.token_price);
    IDO.participate(account, amount_paid, allocation, number_of_tokens_buying);

    let (pmt_amount) = SafeUint256.mul(number_of_tokens_buying, the_sale.token_price);
    let (pmt_success: felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, pmt_amount
    );
    with_attr error_message("AstralyINOContract::participate Participation payment failed") {
        assert pmt_success = TRUE;
    }
    return ();
}

@external
func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    return IDO.withdraw_from_contract();
}

@external
func withdraw_leftovers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    return IDO.withdraw_leftovers();
}

@external
func withdraw_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_id: felt
) {
    alloc_locals;
    IDO.withdraw_tokens(portion_id);

    let (caller) = get_caller_address();
    let participation: Participation = IDO.get_user_participation(caller);
    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), participation.amount_bought);

    if (amt_withdrawing_check == TRUE) {
        let (_current_id: Uint256) = current_id.read();
        let (the_sale: Sale) = get_current_sale();
        batch_mint(the_sale.token, caller, _current_id, participation.amount_bought);
        let (new_id: Uint256) = SafeUint256.add(_current_id, participation.amount_bought);
        current_id.write(new_id);
        TokensWithdrawn.emit(caller, participation.amount_bought);
        return ();
    }

    return ();
}

func batch_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token: felt, to: felt, start_index: Uint256, end_index: Uint256
) {
    let (all_minted) = uint256_eq(start_index, end_index);
    if (all_minted == TRUE) {
        return ();
    }

    IERC721.mint(token, to, start_index);
    let (new_index) = SafeUint256.add(start_index, Uint256(1, 0));
    return batch_mint(token, to, new_index, end_index);
}
