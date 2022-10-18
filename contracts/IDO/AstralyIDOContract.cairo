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
from interfaces.i_AstralyReferral import IAstralyreferral
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

// Times when portions are getting unlocked
@storage_var
func vesting_portions_unlock_time_array(i: felt) -> (res: felt) {
}

// Percent of the participation user can withdraw
@storage_var
func vesting_percent_per_portion_array(i: felt) -> (res: Uint256) {
}

@storage_var
func _referral() -> (res: felt) {
}
// Accumulated performance fees
@storage_var
func performance_fees_acc() -> (res: Uint256) {
}
// Earnings through referrals
@storage_var
func referral_earnings(user: felt) -> (res: Uint256) {
}

//
// Events
//

@event
func IDOCreated(new_ido_contract_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin_address: felt, admin_cut: Uint256
) {
    AstralyAccessControl.initializer(admin_address);
    IDO.initializer(admin_address, admin_cut);

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
func get_performance_fee{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Uint256
) {
    let (res) = IDO.get_performance_fee();
    return (res,);
}

@view
func get_amm_wrapper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: felt
) {
    let (res) = IDO.get_amm_wrapper();
    return (res,);
}

@view
func get_referral_earnings{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt
) -> (res: Uint256) {
    let (res) = referral_earnings.read(user);
    return (res,);
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

@view
func get_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: felt
) {
    let (res) = _referral.read();
    return (res,);
}

//############################################
// #                 EXTERNALS               ##
//############################################

@external
func set_referral{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(referral: felt) {
    AstralyAccessControl.assert_only_owner();
    _referral.write(referral);
    return ();
}

@external
func set_vesting_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _unlocking_times_len: felt, _unlocking_times: felt*, _percents_len: felt, _percents: Uint256*
) {
    AstralyAccessControl.assert_only_owner();

    _set_vesting_params(_unlocking_times_len, _unlocking_times, _percents_len, _percents);

    return ();
}

func _set_vesting_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _unlocking_times_len: felt, _unlocking_times: felt*, _percents_len: felt, _percents: Uint256*
) {
    alloc_locals;

    with_attr error_message("set_vesting_params::Unlocking times array length 0") {
        assert_not_zero(_unlocking_times_len);
    }
    with_attr error_message("set_vesting_params::Percents array length 0") {
        assert_not_zero(_percents_len);
    }
    with_attr error_message(
            "set_vesting_params::Unlocking times and percents arrays different lengths") {
        assert _unlocking_times_len = _percents_len;
    }

    let (local _portion_vesting_precision: Uint256) = portion_vesting_precision.read();
    with_attr error_message("set_vesting_params::Portion vesting precision is zero") {
        let (percision_check: felt) = uint256_lt(Uint256(0, 0), _portion_vesting_precision);
        assert percision_check = TRUE;
    }

    number_of_vesting_portions.write(_percents_len);

    let percent_sum = Uint256(0, 0);
    // # local array_index = 0
    let array_index = 1;

    populate_vesting_params_rec(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, array_index
    );

    let (percent_sum) = array_sum(_percents, _percents_len);
    let (percent_sum_check) = uint256_eq(percent_sum, _portion_vesting_precision);

    with_attr error_message("set_vesting_params::Vesting percentages do not add up") {
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

    with_attr error_message("set_sale_params::Portion vesting percision should be at least 100") {
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
func set_amm_wrapper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _amm_wrapper_address: felt
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_amm_wrapper(_amm_wrapper_address);
    return ();
}

@external
func set_performance_fee{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _performance_fee: Uint256
) {
    AstralyAccessControl.assert_only_owner();
    IDO.set_performance_fee(_performance_fee);
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
    let (decimals) = IERC20.decimals(pmt_token_addr);
    let (local power) = pow(10, decimals);
    let (number_of_tokens_buying: Uint256) = SafeUint256.mul(amount_paid, Uint256(power, 0));
    let (number_of_tokens_buying, _) = SafeUint256.div_rem(
        number_of_tokens_buying, the_sale.token_price
    );
    IDO.participate(account, amount_paid, allocation, number_of_tokens_buying);

    let (pmt_success: felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, amount_paid
    );
    with_attr error_message("participate::Participation payment failed") {
        assert pmt_success = TRUE;
    }
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

    with_attr error_message("withdraw_tokens::Invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }

    with_attr error_message("withdraw_tokens::Portion has not been unlocked yet") {
        let (block_timestamp) = get_block_timestamp();
        assert_le_felt(vesting_portions_unlock_time, block_timestamp);
    }

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(portion_id);

    with_attr error_message("withdraw_tokens::Invalid vesting portion percent") {
        let (valid) = uint256_lt(Uint256(0, 0), vesting_portion_percent);
        assert valid = TRUE;
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
        // Take performance fees
        let (fees) = IDO.get_performance_fees(amt_withdrawing);
        // Take referral fees
        let (referral) = get_referral();
        if (referral != 0) {
            // Compute referral fees
            let (ref_fees) = IAstralyreferral.get_referral_fees(referral, fees);
            let (referrer) = IAstralyreferral.get_referrer(referral, address_caller);
            let (cur_ref_fees) = referral_earnings.read(referrer);
            let (ref_fees_acc) = SafeUint256.add(ref_fees, cur_ref_fees);
            referral_earnings.write(referrer, ref_fees_acc);
            // Accumulate performance fees
            let (cur_fees) = performance_fees_acc.read();
            let (perf_fees) = SafeUint256.sub_lt(fees, ref_fees);
            let (fees_acc) = SafeUint256.add(perf_fees, cur_fees);
            performance_fees_acc.write(fees_acc);
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            // Accumulate performance fees
            let (cur_fees) = performance_fees_acc.read();
            let (fees_acc) = SafeUint256.add(fees, cur_fees);
            performance_fees_acc.write(fees_acc);
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        // Transfer after fees
        let (amt_transfer) = SafeUint256.sub_le(amt_withdrawing, fees);
        let (token_transfer_success: felt) = IERC20.transfer(
            token_address, address_caller, amt_transfer
        );
        with_attr error_message("withdraw_tokens::Token transfer to user failed") {
            assert token_transfer_success = TRUE;
        }

        TokensWithdrawn.emit(user_address=address_caller, amount=amt_transfer);
        return ();
    }
    return ();
}

@external
func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    return IDO.withdraw_from_contract();
}

@external
func withdraw_leftovers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    return IDO.withdraw_leftovers();
}

@external
func withdraw_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (caller) = get_caller_address();
    let (fees) = performance_fees_acc.read();
    let (the_sale) = get_current_sale();
    let token_address = the_sale.token;
    // Reset fees accumulator
    performance_fees_acc.write(Uint256(0, 0));
    let (token_transfer_success: felt) = IERC20.transfer(token_address, caller, fees);
    with_attr error_message("withdraw_fees::Token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    return ();
}

@external
func withdraw_referral_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (caller) = get_caller_address();
    let (fees) = referral_earnings.read(caller);
    with_attr error_message("withdraw_referral_fees::Nothing to withdraw") {
        let (check) = uint256_lt(Uint256(0, 0), fees);
        assert check = TRUE;
    }
    let (the_sale) = get_current_sale();
    let token_address = the_sale.token;
    // Reset fees accumulator
    referral_earnings.write(caller, Uint256(0, 0));
    let (token_transfer_success: felt) = IERC20.transfer(token_address, caller, fees);
    with_attr error_message("withdraw_referral_fees::Token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    return ();
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
        // Take performance fees
        let (fees) = IDO.get_performance_fees(amt_withdrawn_sum);
        // Take referral fees
        let (referral) = get_referral();
        if (referral != 0) {
            // Compute referral fees
            let (ref_fees) = IAstralyreferral.get_referral_fees(referral, fees);
            let (referrer) = IAstralyreferral.get_referrer(referral, address_caller);
            let (cur_ref_fees) = referral_earnings.read(referrer);
            let (ref_fees_acc) = SafeUint256.add(ref_fees, cur_ref_fees);
            referral_earnings.write(referrer, ref_fees_acc);
            // Accumulate performance fees
            let (cur_fees) = performance_fees_acc.read();
            let (perf_fees) = SafeUint256.sub_lt(fees, ref_fees);
            let (fees_acc) = SafeUint256.add(perf_fees, cur_fees);
            performance_fees_acc.write(fees_acc);
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            // Accumulate performance fees
            let (cur_fees) = performance_fees_acc.read();
            let (fees_acc) = SafeUint256.add(fees, cur_fees);
            performance_fees_acc.write(fees_acc);
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        // Transfer after fees
        let (amt_transfer) = SafeUint256.sub_le(amt_withdrawn_sum, fees);
        let (token_transfer_success: felt) = IERC20.transfer(
            token_address, address_caller, amt_transfer
        );
        with_attr error_message("withdraw_multiple_portions::Token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        TokensWithdrawn.emit(user_address=address_caller, amount=amt_transfer);
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
    with_attr error_message("withdraw_multiple_portions_rec::Invalid portion Id") {
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

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(current_portion);
    with_attr error_message("withdraw_multiple_portions_rec::Invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }
    with_attr error_message("withdraw_multiple_portions_rec::Portion has not been unlocked yet") {
        assert_le_felt(vesting_portions_unlock_time, _block_timestamp);
    }

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(current_portion);
    with_attr error_message("withdraw_multiple_portions_rec::Invalid vestion portion percent") {
        let (valid) = uint256_lt(Uint256(0, 0), vesting_portion_percent);
        assert valid = TRUE;
    }

    let (amt_withdrawing_num: Uint256) = SafeUint256.mul(
        participation.amount_bought, vesting_portion_percent
    );
    let (portion_vesting_prsn: Uint256) = portion_vesting_precision.read();
    let (amt_withdrawing, _) = SafeUint256.div_rem(amt_withdrawing_num, portion_vesting_prsn);

    let (the_sum) = SafeUint256.add(amt_withdrawing, sum_of_portions);
    return (amt_sum=the_sum);
}
