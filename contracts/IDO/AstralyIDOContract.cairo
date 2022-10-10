%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_lt_felt
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import get_block_timestamp

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.safemath.library import SafeUint256

from contracts.AstralyAccessControl import AstralyAccessControl
from contracts.utils.Uint256_felt_conv import _uint_to_felt
from contracts.IDO.ido_library import IDO, Sale, Participation, PurchaseRound, Registration

const SALE_OWNER_ROLE = 'SALE_OWNER';

@storage_var
func base_allocation() -> (allocation: Uint256) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt
) {
    AstralyAccessControl.initializer(admin_address);
    IDO.initializer(admin_address);
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
    let (_base_allocation) = base_allocation.read();
    let (res: Uint256) = SafeUint256.mul(Uint256(count, 0), _base_allocation);
    return (res=res);
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
@view
func get_vesting_portion_percent{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_id: felt
) -> (res: Uint256) {
    return IDO.get_vesting_percent_per_portion_array(portion_id);
}

@view
func get_vestion_portion_unlock_time{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(portion_id: felt) -> (res: felt) {
    return IDO.get_vesting_portions_unlock_time_array(portion_id);
}

@view
func get_number_of_vesting_portions{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (res: felt) {
    return IDO.get_number_of_vesting_portions();
}

//############################################
// #                 EXTERNALS               ##
//############################################

@external
func set_vesting_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _unlocking_times_len: felt,
    _unlocking_times: felt*,
    _percents_len: felt,
    _percents: Uint256*,
    _max_vesting_time_shift: felt,
) {
    AstralyAccessControl.assert_only_owner();

    IDO.set_vesting_params(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, _max_vesting_time_shift
    );

    return ();
}

@external
func set_sale_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token_address: felt,
    _sale_owner_address: felt,
    _token_price: Uint256,
    _amount_of_tokens_to_sell: Uint256,
    _sale_end_time: felt,
    _tokens_unlock_time: felt,
    _portion_vesting_precision: Uint256,
    _base_allocation: Uint256,
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_sale_params(
        _token_address,
        _sale_owner_address,
        _token_price,
        _amount_of_tokens_to_sell,
        _sale_end_time,
        _tokens_unlock_time,
        _portion_vesting_precision,
    );
    base_allocation.write(_base_allocation);
    let (winners_max_len_uint, _) = SafeUint256.div_rem(
        _amount_of_tokens_to_sell, _base_allocation
    );
    let (winners_max_len: felt) = _uint_to_felt(winners_max_len_uint);

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
func deposit_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    return IDO.deposit_tokens();
}

@external
func withdraw_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_id: felt
) {
    return IDO.withdraw_tokens(portion_id);
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
func withdraw_multiple_portions{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_ids_len: felt, portion_ids: felt*
) {
    return IDO.withdraw_multiple_portions(portion_ids_len, portion_ids);
}
