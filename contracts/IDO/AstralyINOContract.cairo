%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_lt_felt
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
from contracts.utils.Uint256_felt_conv import _uint_to_felt
from contracts.utils import is_lt
from InterfaceAll import IAstralyIDOFactory, IXoroshiro, IERC721

const SALE_OWNER_ROLE = 'SALE_OWNER';

@storage_var
func current_id() -> (res: Uint256) {
}

@event
func INOCreated(new_ino_contract_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt
) {
    AstralyAccessControl.initializer(admin_address);
    IDO.initializer(admin_address);

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
) -> (res: felt) {
    let count: felt = IDO.get_allocation(address);
    return (res=count);
}

@view
func is_winner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(address: felt) -> (
    res: felt
) {
    with_attr error_message("AstralyINOContract::isWinner Registration window not closed") {
        let (the_reg) = get_registration();
        let (block_timestamp) = get_block_timestamp();
        assert_lt_felt(the_reg.registration_time_ends, block_timestamp);
    }

    let count: felt = IDO.get_allocation(address);
    if (count == 0) {
        return (res=FALSE);
    }

    return (res=TRUE);
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
}(amount_paid: Uint256, test: Uint256, sig_len: felt, sig: felt*) {
    IDO.participate(amount_paid, test, sig_len, sig);
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
    let amt_withdrawing: Uint256 = IDO.withdraw_tokens(portion_id);
    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), amt_withdrawing);

    if (amt_withdrawing_check == TRUE) {
        let (_current_id: Uint256) = current_id.read();
        let (the_sale: Sale) = get_current_sale();
        let (address_caller: felt) = get_caller_address();
        let participation: Participation = IDO.get_user_participation(address_caller);
        batch_mint(the_sale.token, address_caller, _current_id, participation.amount_bought);
        let (new_id: Uint256) = SafeUint256.add(_current_id, participation.amount_bought);
        current_id.write(new_id);
        TokensWithdrawn.emit(user_address=address_caller, amount=participation.amount_bought);
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
