%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_lt_felt, assert_le_felt, assert_not_zero
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_lt, uint256_le
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.safemath.library import SafeUint256

from contracts.AstralyAccessControl import AstralyAccessControl
from contracts.utils.Uint256_felt_conv import _uint_to_felt
from contracts.utils.AstralyConstants import DAYS_30
from contracts.IDO.ido_library import (
    IDO,
    Sale,
    Participation,
    PurchaseRound,
    Registration,
    TokensWithdrawn,
)

const SALE_OWNER_ROLE = 'SALE_OWNER';

@storage_var
func base_allocation() -> (allocation: Uint256) {
}

// Precision for percent for portion vesting
@storage_var
func portion_vesting_precision() -> (res: Uint256) {
}

@storage_var
func number_of_vesting_portions() -> (res: felt) {
}

// Max vesting time shift
@storage_var
func max_vesting_time_shift() -> (res: felt) {
}

// Times when portions are getting unlocked
@storage_var
func vesting_portions_unlock_time_array(i: felt) -> (res: felt) {
}

// Percent of the participation user can withdraw
@storage_var
func vesting_percent_per_portion_array(i: felt) -> (res: Uint256) {
}

//
// Events
//

@event
func IDOCreated(new_ido_contract_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt
) {
    AstralyAccessControl.initializer(admin_address);
    IDO.initializer(admin_address);

    let (address_this: felt) = get_contract_address();
    IDOCreated.emit(address_this);
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
    return vesting_percent_per_portion_array.read(portion_id);
}

@view
func get_vestion_portion_unlock_time{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(portion_id: felt) -> (res: felt) {
    return vesting_portions_unlock_time_array.read(portion_id);
}

@view
func get_number_of_vesting_portions{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (res: felt) {
    return number_of_vesting_portions.read();
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

    _set_vesting_params(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, _max_vesting_time_shift
    );

    return ();
}

func _set_vesting_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _unlocking_times_len: felt,
    _unlocking_times: felt*,
    _percents_len: felt,
    _percents: Uint256*,
    _max_vesting_time_shift: felt,
) {
    alloc_locals;

    with_attr error_message(
            "AstralyIDOContract::set_vesting_params unlocking times array length 0") {
        assert_not_zero(_unlocking_times_len);
    }
    with_attr error_message("AstralyIDOContract::set_vesting_params percents array length 0") {
        assert_not_zero(_percents_len);
    }
    with_attr error_message(
            "AstralyIDOContract::set_vesting_params unlocking times and percents arrays different lengths") {
        assert _unlocking_times_len = _percents_len;
    }

    let (local _portion_vesting_precision: Uint256) = portion_vesting_precision.read();
    with_attr error_message(
            "AstralyIDOContract::set_vesting_params portion vesting precision is zero") {
        let (percision_check: felt) = uint256_lt(Uint256(0, 0), _portion_vesting_precision);
        assert percision_check = TRUE;
    }

    with_attr error_message(
            "AstralyIDOContract::set_vesting_params max vesting time shift more than 30 days") {
        assert_le_felt(_max_vesting_time_shift, DAYS_30);
    }

    max_vesting_time_shift.write(_max_vesting_time_shift);
    number_of_vesting_portions.write(_percents_len);

    let percent_sum = Uint256(0, 0);
    // # local array_index = 0
    let array_index = 1;

    populate_vesting_params_rec(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, array_index
    );

    let (percent_sum) = array_sum(_percents, _percents_len);
    let (percent_sum_check) = uint256_eq(percent_sum, _portion_vesting_precision);

    with_attr error_message(
            "AstralyIDOContract::set_vesting_params Vesting percentages do not add up") {
        assert percent_sum_check = TRUE;
    }

    return ();
}

func array_sum{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    arr: Uint256*, size: felt
) -> (sum: Uint256) {
    if (size == 0) {
        // parenthesis required for return statement
        return (sum=Uint256(0, 0));
    }

    // recursive call to array_sum, arr = arr[0],
    let (sum_of_rest) = array_sum(arr=arr + Uint256.SIZE, size=size - 1);
    // [...] dereferences to value of memory address which is first element of arr
    // recurisvely calls array_sum with arr+1 which is next element in arr
    // recursion stops when size == 0
    // return (sum=[arr] + sum_of_rest)
    let (the_sum) = SafeUint256.add([arr], sum_of_rest);
    return (sum=the_sum);
}

func populate_vesting_params_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _unlocking_times_len: felt,
    _unlocking_times: felt*,
    _percents_len: felt,
    _percents: Uint256*,
    _array_index: felt,
) {
    alloc_locals;
    assert _unlocking_times_len = _percents_len;

    if (_unlocking_times_len == 0) {
        return ();
    }

    let percent0 = _percents[0];
    vesting_portions_unlock_time_array.write(_array_index, _unlocking_times[0]);
    vesting_percent_per_portion_array.write(_array_index, _percents[0]);
    return populate_vesting_params_rec(
        _unlocking_times_len=_unlocking_times_len - 1,
        _unlocking_times=_unlocking_times + 1,
        _percents_len=_percents_len - 1,
        _percents=_percents + Uint256.SIZE,
        _array_index=_array_index + 1,
    );
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

    with_attr error_message(
            "AstralyIDOContract::set_sale_params portion vesting percision should be at least 100") {
        let (vesting_precision_check: felt) = uint256_le(
            Uint256(100, 0), _portion_vesting_precision
        );
        assert vesting_precision_check = TRUE;
    }
    portion_vesting_precision.write(_portion_vesting_precision);

    IDO.set_sale_params(
        _token_address,
        _sale_owner_address,
        _token_price,
        _amount_of_tokens_to_sell,
        _sale_end_time,
        _tokens_unlock_time,
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
    alloc_locals;
    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(portion_id);

    with_attr error_message(
            "AstralyIDOContract::withdraw_tokens invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }

    with_attr error_message(
            "AstralyIDOContract::withdraw_tokens Portion has not been unlocked yet") {
        let (block_timestamp) = get_block_timestamp();
        assert_le_felt(vesting_portions_unlock_time, block_timestamp);
    }

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(portion_id);

    with_attr error_message("AstralyIDOContract::withdraw_tokens invlaid vestion portion percent") {
        uint256_lt(Uint256(0, 0), vesting_portion_percent);
    }

    let (address_caller: felt) = get_caller_address();

    let participation: Participation = IDO.get_user_participation(address_caller);

    IDO.withdraw_tokens(portion_id);
    let (amt_withdrawing_num: Uint256) = SafeUint256.mul(
        participation.amount_bought, vesting_portion_percent
    );
    let (portion_vesting_prsn: Uint256) = portion_vesting_precision.read();
    let (amt_withdrawing, _) = SafeUint256.div_rem(amt_withdrawing_num, portion_vesting_prsn);

    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), amt_withdrawing);
    if (amt_withdrawing_check == TRUE) {
        let (the_sale) = IDO.get_current_sale();
        let token_address = the_sale.token;
        let (token_transfer_success: felt) = IERC20.transfer(
            token_address, address_caller, amt_withdrawing
        );
        with_attr error_message("AstralyIDOContract::withdraw_tokens token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        TokensWithdrawn.emit(user_address=address_caller, amount=amt_withdrawing);
        return ();
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
func withdraw_multiple_portions{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_ids_len: felt, portion_ids: felt*
) {
    return _withdraw_multiple_portions(portion_ids_len, portion_ids);
}

func _withdraw_multiple_portions{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_ids_len: felt, portion_ids: felt*
) {
    alloc_locals;
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = get_current_sale();
    let (block_timestamp) = get_block_timestamp();
    let participation = IDO.get_user_participation(address_caller);

    let (amt_withdrawn_sum: Uint256) = withdraw_multiple_portions_rec(
        portion_ids_len, portion_ids, block_timestamp, address_caller
    );
    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), amt_withdrawn_sum);
    if (amt_withdrawing_check == TRUE) {
        let token_address = the_sale.token;
        let (token_transfer_success: felt) = IERC20.transfer(
            token_address, address_caller, amt_withdrawn_sum
        );
        with_attr error_message(
                "AstralyIDOContract::withdraw_multiple_portions token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        TokensWithdrawn.emit(user_address=address_caller, amount=amt_withdrawn_sum);
        return ();
    }

    return ();
}

func withdraw_multiple_portions_rec{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(_portion_ids_len: felt, _portion_ids: felt*, _block_timestamp: felt, _address_caller: felt) -> (
    amt_sum: Uint256
) {
    alloc_locals;

    if (_portion_ids_len == 0) {
        return (amt_sum=Uint256(0, 0));
    }

    let current_portion = _portion_ids[0];
    let participation = IDO.get_user_participation(_address_caller);
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec Invalid portion Id") {
        assert_lt_felt(participation.last_portion_withdrawn, current_portion);
    }
    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        last_portion_withdrawn=current_portion,
    );
    IDO.set_user_participation(_address_caller, participation_upd);

    let (sum_of_portions) = withdraw_multiple_portions_rec(
        _portion_ids_len=_portion_ids_len - 1,
        _portion_ids=_portion_ids + 1,
        _block_timestamp=_block_timestamp,
        _address_caller=_address_caller,
    );

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(
        current_portion
    );
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec Portion has not been unlocked yet") {
        assert_le_felt(vesting_portions_unlock_time, _block_timestamp);
    }

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(current_portion);
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec invlaid vestion portion percent") {
        uint256_lt(Uint256(0, 0), vesting_portion_percent);
    }

    let (amt_withdrawing_num: Uint256) = SafeUint256.mul(
        participation.amount_bought, vesting_portion_percent
    );
    let (portion_vesting_prsn: Uint256) = portion_vesting_precision.read();
    let (amt_withdrawing, _) = SafeUint256.div_rem(amt_withdrawing_num, portion_vesting_prsn);

    let (the_sum) = SafeUint256.add(amt_withdrawing, sum_of_portions);
    return (amt_sum=the_sum);
}
