%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import (
    assert_nn_le,
    assert_not_equal,
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
)
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_eq,
    uint256_le,
    uint256_lt,
    uint256_check,
)
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.token.erc20.IERC20 import IERC20
from contracts.AstralyAccessControl import AstralyAccessControl
from openzeppelin.security.safemath.library import SafeUint256

from contracts.utils.AstralyConstants import DAYS_30
from contracts.utils.Uint256_felt_conv import _felt_to_uint, _uint_to_felt
from contracts.utils.Math64x61 import (
    Math64x61_fromUint256,
    Math64x61_toUint256,
    Math64x61_div,
    Math64x61_fromFelt,
    Math64x61_toFelt,
    Math64x61_mul,
    Math64x61_add,
)
from InterfaceAll import IAstralyIDOFactory, IXoroshiro, XOROSHIRO_ADDR, IAccount

const Math64x61_BOUND_LOCAL = 2 ** 64;
const SALE_OWNER_ROLE = 'SALE_OWNER';

struct Sale {
    // Token being sold (interface)
    token: felt,
    // Is sale created (boolean)
    is_created: felt,
    // Are earnings withdrawn (boolean)
    raised_funds_withdrawn: felt,
    // Is leftover withdrawn (boolean)
    leftover_withdrawn: felt,
    // Have tokens been deposited (boolean)
    tokens_deposited: felt,
    // Address of sale owner
    sale_owner: felt,
    // Price of the token quoted - needed as its the price set for the IDO
    token_price: Uint256,
    // Amount of tokens to sell
    amount_of_tokens_to_sell: Uint256,
    // Total tokens being sold
    total_tokens_sold: Uint256,
    // Total Raised (what are using to track this?)
    total_raised: Uint256,
    // Sale end time
    sale_end: felt,
    // When tokens can be withdrawn
    tokens_unlock_time: felt,
    // Number of users participated in the sale
    number_of_participants: Uint256,
}

struct Participation {
    amount_bought: Uint256,
    amount_paid: Uint256,
    time_participated: felt,
    // member round_id : felt
    last_portion_withdrawn: felt,
}

struct Registration {
    registration_time_starts: felt,
    registration_time_ends: felt,
    number_of_registrants: Uint256,
}

struct Purchase_Round {
    time_starts: felt,
    time_ends: felt,
    max_participation: Uint256,
}

struct Distribution_Round {
    time_starts: felt,
}

// Sale
@storage_var
func sale() -> (res: Sale) {
}

// Registration
@storage_var
func registration() -> (res: Registration) {
}

@storage_var
func purchase_round() -> (res: Purchase_Round) {
}

// Mapping user to his participation
@storage_var
func user_to_participation(user_address: felt) -> (res: Participation) {
}

// Mapping user to number of allocations
@storage_var
func address_to_allocations(user_address: felt) -> (res: Uint256) {
}

// total allocations given
@storage_var
func total_allocations_given() -> (res: Uint256) {
}

// mapping user to is registered or not
@storage_var
func is_registered(user_address: felt) -> (res: felt) {
}

// mapping user to is participated or not
@storage_var
func has_participated(user_address: felt) -> (res: felt) {
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
func number_of_vesting_portions() -> (res: felt) {
}

// Precision for percent for portion vesting
@storage_var
func portion_vesting_precision() -> (res: Uint256) {
}

// Max vesting time shift
@storage_var
func max_vesting_time_shift() -> (res: felt) {
}

@storage_var
func ido_factory_contract_address() -> (res: felt) {
}

@storage_var
func admin_address() -> (res: felt) {
}

@storage_var
func ido_allocation() -> (res: Uint256) {
}

@event
func tokens_sold(user_address: felt, amount: Uint256) {
}

@event
func user_registered(user_address: felt) {
}

@event
func token_price_set(new_price: Uint256) {
}

@event
func allocation_computed(allocation: Uint256, sold: Uint256) {
}

@event
func tokens_withdrawn(user_address: felt, amount: Uint256) {
}

@event
func sale_created(
    sale_owner_address: felt,
    token_price: Uint256,
    amount_of_tokens_to_sell: Uint256,
    sale_end: felt,
    tokens_unlock_time: felt,
) {
}

@event
func registration_time_set(registration_time_starts: felt, registration_time_ends: felt) {
}

@event
func purchase_round_set(
    purchase_time_starts: felt, purchase_time_ends: felt, max_participation: Uint256
) {
}

@event
func IDO_Created(new_ido_contract_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _admin_address: felt
) {
    assert_not_zero(_admin_address);
    AstralyAccessControl.initializer(_admin_address);
    admin_address.write(_admin_address);

    let (caller: felt) = get_caller_address();
    ido_factory_contract_address.write(caller);

    let (address_this: felt) = get_contract_address();
    IDO_Created.emit(address_this);
    return ();
}

//############################################
// #                 GETTERS                 ##
//############################################

@view
func get_ido_launch_date{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: felt
) {
    let (the_reg) = registration.read();
    return (res=the_reg.registration_time_starts);
}

@view
func get_current_sale{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Sale
) {
    let (the_sale) = sale.read();
    return (res=the_sale);
}

@view
func get_user_info{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account: felt
) -> (
    participation: Participation, allocations: Uint256, is_registered: felt, has_participated: felt
) {
    let (_participation) = user_to_participation.read(account);
    let (_allocations) = address_to_allocations.read(account);
    let (_is_registered) = is_registered.read(account);
    let (_has_participated) = has_participated.read(account);
    return (
        participation=_participation,
        allocations=_allocations,
        is_registered=_is_registered,
        has_participated=_has_participated,
    );
}

@view
func get_purchase_round{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Purchase_Round
) {
    let (round) = purchase_round.read();
    return (res=round);
}

@view
func get_registration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    res: Registration
) {
    let (_registration) = registration.read();
    return (res=_registration);
}

@view
func get_vesting_portion_percent{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_id: felt
) -> (res: Uint256) {
    let (percent) = vesting_percent_per_portion_array.read(portion_id);
    return (res=percent);
}

@view
func get_vestion_portion_unlock_time{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(portion_id: felt) -> (res: felt) {
    let (unlock_time) = vesting_portions_unlock_time_array.read(portion_id);
    return (res=unlock_time);
}

@view
func get_number_of_vesting_portions{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (res: felt) {
    let (nbr_of_portions) = number_of_vesting_portions.read();
    return (res=nbr_of_portions);
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
    alloc_locals;
    AstralyAccessControl.assert_only_owner();

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
        assert_le(_max_vesting_time_shift, DAYS_30);
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

@external
func set_sale_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _token_address: felt,
    _sale_owner_address: felt,
    _token_price: Uint256,
    _amount_of_tokens_to_sell: Uint256,
    _sale_end_time: felt,
    _tokens_unlock_time: felt,
    _portion_vesting_precision: Uint256,
) {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    with_attr error_message("AstralyIDOContract::set_sale_params Sale is already created") {
        assert the_sale.is_created = FALSE;
    }
    with_attr error_message("AstralyIDOContract::set_sale_params Sale owner address can not be 0") {
        assert_not_zero(_sale_owner_address);
    }
    with_attr error_message("AstralyIDOContract::set_sale_params Token address can not be 0") {
        assert_not_zero(_token_address);
    }
    with_attr error_message(
            "AstralyIDOContract::set_sale_params IDO Token price must be greater than zero") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), _token_price);
        assert token_price_check = TRUE;
    }
    with_attr error_message(
            "AstralyIDOContract::set_sale_params Number of IDO Tokens to sell must be greater than zero") {
        let (token_to_sell_check: felt) = uint256_lt(Uint256(0, 0), _amount_of_tokens_to_sell);
        assert token_to_sell_check = TRUE;
    }
    with_attr error_message("AstralyIDOContract::set_sale_params Sale end time in the past") {
        assert_lt(block_timestamp, _sale_end_time);
    }
    with_attr error_message("AstralyIDOContract::set_sale_params Tokens unlock time in the past") {
        assert_lt(block_timestamp, _tokens_unlock_time);
    }
    with_attr error_message(
            "AstralyIDOContract::set_sale_params portion vesting percision should be at least 100") {
        let (vesting_precision_check: felt) = uint256_le(
            Uint256(100, 0), _portion_vesting_precision
        );
        assert vesting_precision_check = TRUE;
    }

    // set params
    let new_sale = Sale(
        token=_token_address,
        is_created=TRUE,
        raised_funds_withdrawn=FALSE,
        leftover_withdrawn=FALSE,
        tokens_deposited=FALSE,
        sale_owner=_sale_owner_address,
        token_price=_token_price,
        amount_of_tokens_to_sell=_amount_of_tokens_to_sell,
        total_tokens_sold=Uint256(0, 0),
        total_raised=Uint256(0, 0),
        sale_end=_sale_end_time,
        tokens_unlock_time=_tokens_unlock_time,
        number_of_participants=Uint256(0, 0),
    );
    sale.write(new_sale);
    AstralyAccessControl.grant_role(SALE_OWNER_ROLE, _sale_owner_address);
    // Set portion vesting precision
    portion_vesting_precision.write(_portion_vesting_precision);
    // emit event
    sale_created.emit(
        sale_owner_address=_sale_owner_address,
        token_price=_token_price,
        amount_of_tokens_to_sell=_amount_of_tokens_to_sell,
        sale_end=_sale_end_time,
        tokens_unlock_time=_tokens_unlock_time,
    );
    return ();
}

@external
func set_sale_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _sale_token_address: felt
) {
    AstralyAccessControl.assert_only_owner();
    let (the_sale) = sale.read();
    let upd_sale = Sale(
        token=_sale_token_address,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=the_sale.leftover_withdrawn,
        tokens_deposited=the_sale.tokens_deposited,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);
    return ();
}

@external
func set_registration_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _registration_time_starts: felt, _registration_time_ends: felt
) {
    AstralyAccessControl.assert_only_owner();
    let (the_sale) = sale.read();
    let (the_reg) = registration.read();
    let (block_timestamp) = get_block_timestamp();
    with_attr error_message("AstralyIDOContract::set_registration_time Sale not created yet") {
        assert the_sale.is_created = TRUE;
    }
    // with_attr error_message(
    //         "AstralyIDOContract::set_registration_time the registration start time is already set"):
    //     assert the_reg.registration_time_starts = 0
    // end
    with_attr error_message(
            "AstralyIDOContract::set_registration_time registration start/end times issue") {
        assert_le(block_timestamp, _registration_time_starts);
        assert_lt(_registration_time_starts, _registration_time_ends);
    }
    with_attr error_message(
            "AstralyIDOContract::set_registration_time registration end has to be before sale end") {
        assert_lt(_registration_time_ends, the_sale.sale_end);
    }
    let upd_reg = Registration(
        registration_time_starts=_registration_time_starts,
        registration_time_ends=_registration_time_ends,
        number_of_registrants=the_reg.number_of_registrants,
    );
    registration.write(upd_reg);
    registration_time_set.emit(
        registration_time_starts=_registration_time_starts,
        registration_time_ends=_registration_time_ends,
    );
    return ();
}

@external
func set_purchase_round_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _purchase_time_starts: felt, _purchase_time_ends: felt, max_participation: Uint256
) {
    AstralyAccessControl.assert_only_owner();
    let (the_reg) = registration.read();
    let (the_purchase) = purchase_round.read();
    with_attr error_message("AstralyIDOContract::set_purchase_round_params Bad input") {
        assert_not_zero(_purchase_time_starts);
        assert_not_zero(_purchase_time_ends);
    }
    with_attr error_message(
            "AstralyIDOContract::set_purchase_round_params end time must be after start end") {
        assert_lt(_purchase_time_starts, _purchase_time_ends);
    }
    with_attr error_message("AstralyIDOContract::max_participation must be non-null") {
        let (participation_check: felt) = uint256_lt(Uint256(0, 0), max_participation);
        assert participation_check = TRUE;
    }
    with_attr error_message(
            "AstralyIDOContract::set_purchase_round_params registration time not set yet") {
        assert_not_zero(the_reg.registration_time_starts);
        assert_not_zero(the_reg.registration_time_ends);
    }
    with_attr error_message(
            "AstralyIDOContract::set_purchase_round_params start time must be after registration end") {
        assert_lt(the_reg.registration_time_ends, _purchase_time_starts);
    }
    let upd_purchase = Purchase_Round(
        time_starts=_purchase_time_starts,
        time_ends=_purchase_time_ends,
        max_participation=max_participation,
    );
    purchase_round.write(upd_purchase);
    purchase_round_set.emit(
        purchase_time_starts=_purchase_time_starts,
        purchase_time_ends=_purchase_time_ends,
        max_participation=max_participation,
    );
    return ();
}

@external
func register_user{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(signature_len: felt, signature: felt*, signature_expiration: felt) -> (res: felt) {
    alloc_locals;
    let (the_reg) = registration.read();
    let (block_timestamp) = get_block_timestamp();
    let (caller) = get_caller_address();
    let (the_sale) = sale.read();

    with_attr error_message("AstralyIDOContract::register_user Registration window is closed") {
        assert_le(the_reg.registration_time_starts, block_timestamp);
        assert_le(block_timestamp, the_reg.registration_time_ends);
    }
    with_attr error_message("AstralyIDOContract::register_user invalid signature") {
        check_registration_signature(signature_len, signature, signature_expiration, caller);
    }
    with_attr error_message("AstralyIDOContract::register_user signature expired") {
        assert_lt(block_timestamp, signature_expiration);
    }
    let (is_user_reg) = is_registered.read(caller);
    with_attr error_message("AstralyIDOContract::register_user user already registered") {
        assert is_user_reg = FALSE;
    }

    // Save user registration
    is_registered.write(caller, TRUE);
    // Increment number of registered users
    let (local registrants_sum: Uint256) = SafeUint256.add(
        the_reg.number_of_registrants, Uint256(low=1, high=0)
    );

    let upd_reg = Registration(
        registration_time_starts=the_reg.registration_time_starts,
        registration_time_ends=the_reg.registration_time_ends,
        number_of_registrants=registrants_sum,
    );
    registration.write(upd_reg);
    user_registered.emit(user_address=caller);
    return (res=TRUE);
}

@external
func participate{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(amount_paid: Uint256, amount: Uint256, sig_len: felt, sig: felt*) {
    alloc_locals;
    let (account: felt) = get_caller_address();
    with_attr error_message("AstralyIDOContract::participate invalid signature") {
        check_participation_signature(sig_len, sig, account, amount);
    }
    _participate(account, amount_paid, amount);
    return ();
}

func _participate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account: felt, amount_paid: Uint256, amount: Uint256
) {
    alloc_locals;
    let (address_this: felt) = get_contract_address();
    let (block_timestamp) = get_block_timestamp();
    let (the_round) = purchase_round.read();

    // Validations
    with_attr error_message("AstralyIDOContract::participate Crossing max participation") {
        let (amount_paid_check: felt) = uint256_le(amount_paid, the_round.max_participation);
        assert amount_paid_check = TRUE;
    }
    with_attr error_message("AstralyIDOContract::participate Purchase round has not started yet") {
        assert_le(the_round.time_starts, block_timestamp);
    }
    let (user_participated) = has_participated.read(account);
    with_attr error_message("AstralyIDOContract::participate user participated") {
        assert user_participated = FALSE;
    }
    with_attr error_message("AstralyIDOContract::participate Purchase round is over") {
        assert_le(block_timestamp, the_round.time_ends);
    }

    // with_attr error_message("AstralyIDOContract::participate Account address is the zero address") {
    //     assert_not_zero(account);
    // }
    // with_attr error_message("AstralyIDOContract::participate Amount paid is zero") {
    //     let (amount_paid_check: felt) = uint256_lt(Uint256(0, 0), amount_paid);
    //     assert amount_paid_check = TRUE;
    // }

    let (the_sale) = sale.read();
    with_attr error_message("AstralyIDOContract::participate the IDO token price is not set") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), the_sale.token_price);
        assert token_price_check = TRUE;
    }

    let (factory_address) = ido_factory_contract_address.read();
    let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
        contract_address=factory_address
    );
    with_attr error_message("AstralyIDOContract::participate Payment token address not set") {
        assert_not_zero(pmt_token_addr);
    }

    let (decimals) = IERC20.decimals(pmt_token_addr);
    let (local power) = pow(10, decimals);
    let (number_of_tokens_buying: Uint256) = SafeUint256.mul(amount_paid, Uint256(power, 0));
    let (number_of_tokens_buying_mod, _) = SafeUint256.div_rem(
        number_of_tokens_buying, the_sale.token_price
    );

    // Must buy more than 0 tokens
    with_attr error_message("AstralyIDOContract::participate Can't buy 0 tokens") {
        let (is_tokens_buying_valid: felt) = uint256_lt(Uint256(0, 0), number_of_tokens_buying_mod);
        assert is_tokens_buying_valid = TRUE;
    }

    // Check user allocation
    with_attr error_message("AstralyIDOContract::participate Exceeding allowance") {
        let (valid_allocation: felt) = uint256_le(number_of_tokens_buying_mod, amount);
        assert valid_allocation = TRUE;
    }

    // Require that amountOfTokensBuying is less than sale token leftover cap
    with_attr error_message("AstralyIDOContract::participate Not enough tokens to sell") {
        let (tokens_left) = SafeUint256.sub_le(
            the_sale.amount_of_tokens_to_sell, the_sale.total_tokens_sold
        );
        let (enough_tokens: felt) = uint256_le(number_of_tokens_buying_mod, tokens_left);
        assert enough_tokens = TRUE;
    }

    // Increase amount of sold tokens
    let (local total_tokens_sum: Uint256) = SafeUint256.add(
        the_sale.total_tokens_sold, number_of_tokens_buying_mod
    );

    // Increase total amount raised
    let (local total_raised_sum: Uint256) = SafeUint256.add(the_sale.total_raised, amount_paid);

    // Increment number of participants in the Sale.
    let (local number_of_participants_sum: Uint256) = SafeUint256.add(
        the_sale.number_of_participants, Uint256(1, 0)
    );

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=the_sale.leftover_withdrawn,
        tokens_deposited=the_sale.tokens_deposited,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=total_tokens_sum,
        total_raised=total_raised_sum,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        number_of_participants=number_of_participants_sum,
    );
    sale.write(upd_sale);

    // Add participation for user.
    let new_purchase = Participation(
        amount_bought=number_of_tokens_buying_mod,
        amount_paid=amount_paid,
        time_participated=block_timestamp,
        last_portion_withdrawn=0,
    );
    user_to_participation.write(account, new_purchase);

    has_participated.write(account, TRUE);

    let (pmt_success: felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, amount_paid
    );
    with_attr error_message("AstralyIDOContract::participate Participation payment failed") {
        assert pmt_success = TRUE;
    }
    tokens_sold.emit(user_address=account, amount=number_of_tokens_buying_mod);
    return ();
}

@external
func deposit_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = sale.read();
    with_attr error_message(
            "AstralyIDOContract::deposit_tokens Tokens deposit can be done only once") {
        assert the_sale.tokens_deposited = FALSE;
    }
    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=the_sale.leftover_withdrawn,
        tokens_deposited=TRUE,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);

    let token_address = the_sale.token;
    let tokens_to_transfer = the_sale.amount_of_tokens_to_sell;
    let (transfer_success: felt) = IERC20.transferFrom(
        token_address, address_caller, address_this, tokens_to_transfer
    );
    with_attr error_message("AstralyIDOContract::deposit_tokens token transfer failed") {
        assert transfer_success = TRUE;
    }
    return ();
}

@external
func withdraw_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_id: felt
) {
    alloc_locals;
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    let (participation) = user_to_participation.read(address_caller);

    with_attr error_message("AstralyIDOContract::withdraw_tokens portion id can't be zero") {
        assert_not_zero(portion_id);
    }

    with_attr error_message("AstralyIDOContract::withdraw_tokens Tokens can not be withdrawn yet") {
        assert_le(the_sale.tokens_unlock_time, block_timestamp);
    }

    with_attr error_message("AstralyIDOContract::withdraw_tokens Invlaid portion id") {
        assert_le(participation.last_portion_withdrawn, portion_id);
    }

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(portion_id);

    with_attr error_message(
            "AstralyIDOContract::withdraw_tokens invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }

    with_attr error_message(
            "AstralyIDOContract::withdraw_tokens Portion has not been unlocked yet") {
        assert_le(vesting_portions_unlock_time, block_timestamp);
    }

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(portion_id);

    with_attr error_message("AstralyIDOContract::withdraw_tokens invlaid vestion portion percent") {
        uint256_lt(Uint256(0, 0), vesting_portion_percent);
    }

    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        last_portion_withdrawn=portion_id,
    );
    user_to_participation.write(address_caller, participation_upd);

    let (amt_withdrawing_num: Uint256) = SafeUint256.mul(
        participation.amount_bought, vesting_portion_percent
    );
    let (portion_vesting_prsn: Uint256) = portion_vesting_precision.read();
    let (amt_withdrawing, _) = SafeUint256.div_rem(amt_withdrawing_num, portion_vesting_prsn);

    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), amt_withdrawing);
    if (amt_withdrawing_check == TRUE) {
        let token_address = the_sale.token;
        let (token_transfer_success: felt) = IERC20.transfer(
            token_address, address_caller, amt_withdrawing
        );
        with_attr error_message("AstralyIDOContract::withdraw_tokens token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        tokens_withdrawn.emit(user_address=address_caller, amount=amt_withdrawing);

        return ();
    } else {
        return ();
    }
}

@external
func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (factory_address) = ido_factory_contract_address.read();
    let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
        contract_address=factory_address
    );
    let (contract_balance: Uint256) = IERC20.balanceOf(pmt_token_addr, address_this);
    let (token_transfer_success: felt) = IERC20.transfer(
        pmt_token_addr, address_caller, contract_balance
    );
    with_attr error_message("AstralyIDOContract::withdraw_from_contract token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    let (the_sale) = sale.read();
    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=TRUE,
        leftover_withdrawn=the_sale.leftover_withdrawn,
        tokens_deposited=the_sale.tokens_deposited,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);
    return ();
}

@external
func withdraw_leftovers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (factory_address) = ido_factory_contract_address.read();
    let (the_sale) = sale.read();
    let (contract_balance: Uint256) = IERC20.balanceOf(the_sale.token, address_this);
    let (token_transfer_success: felt) = IERC20.transfer(
        the_sale.token, address_caller, contract_balance
    );
    with_attr error_message("AstralyIDOContract::withdraw_leftovers token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=TRUE,
        tokens_deposited=the_sale.tokens_deposited,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);
    return ();
}

@external
func withdraw_multiple_portions{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    portion_ids_len: felt, portion_ids: felt*
) {
    alloc_locals;
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    let (participation) = user_to_participation.read(address_caller);

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

        tokens_withdrawn.emit(user_address=address_caller, amount=amt_withdrawn_sum);
        return ();
    } else {
        return ();
    }
}

//############################################
// #                 INTERNALS              ##
//############################################

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
    let (participation) = user_to_participation.read(_address_caller);
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec Invalid portion Id") {
        assert_lt(participation.last_portion_withdrawn, current_portion);
    }
    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        last_portion_withdrawn=current_portion,
    );
    user_to_participation.write(_address_caller, participation_upd);

    let (sum_of_portions) = withdraw_multiple_portions_rec(
        _portion_ids_len=_portion_ids_len - 1,
        _portion_ids=_portion_ids + 1,
        _block_timestamp=_block_timestamp,
        _address_caller=_address_caller,
    );

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(current_portion);
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec invalid portion vesting unlock time") {
        assert_not_zero(vesting_portions_unlock_time);
    }
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions_rec Portion has not been unlocked yet") {
        assert_le(vesting_portions_unlock_time, _block_timestamp);
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

func get_random_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    rnd: felt
) {
    let (ido_factory_address) = ido_factory_contract_address.read();
    let (rnd_nbr_gen_addr) = IAstralyIDOFactory.get_random_number_generator_address(
        contract_address=ido_factory_address
    );
    with_attr error_message(
            "AstralyIDOContract::get_random_number random number generator address not set in the factory") {
        assert_not_zero(rnd_nbr_gen_addr);
    }
    let (rnd_felt) = IXoroshiro.next(contract_address=rnd_nbr_gen_addr);
    with_attr error_message("AstralyIDOContract::get_random_number invalid random number value") {
        assert_not_zero(rnd_felt);
    }
    return (rnd=rnd_felt);
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
    // vesting_percent_per_portion_array.write(_array_index, _percents[0])
    vesting_percent_per_portion_array.write(_array_index, percent0);
    return populate_vesting_params_rec(
        _unlocking_times_len=_unlocking_times_len - 1,
        _unlocking_times=_unlocking_times + 1,
        _percents_len=_percents_len - 1,
        _percents=_percents + Uint256.SIZE,
        _array_index=_array_index + 1,
    );
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

@view
func check_registration_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, ecdsa_ptr: SignatureBuiltin*, range_check_ptr
}(sig_len: felt, sig: felt*, sig_expiration_timestamp: felt, caller: felt) {
    alloc_locals;
    let (admin) = admin_address.read();
    let (this) = get_contract_address();

    let (user_hash) = hash2{hash_ptr=pedersen_ptr}(sig_expiration_timestamp, caller);
    let (final_hash) = hash2{hash_ptr=pedersen_ptr}(user_hash, this);

    // Verify the user's signature.
    let (is_valid) = IAccount.isValidSignature(admin, final_hash, sig_len, sig);
    assert is_valid = TRUE;
    return ();
}

@view
func check_participation_signature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(sig_len: felt, sig: felt*, caller: felt, amount: Uint256) {
    alloc_locals;
    let (admin) = admin_address.read();
    let (this) = get_contract_address();

    let (hash1) = hash2{hash_ptr=pedersen_ptr}(caller, amount.low);
    let (hash2_) = hash2{hash_ptr=pedersen_ptr}(hash1, amount.high);
    let (hash3) = hash2{hash_ptr=pedersen_ptr}(hash2_, this);

    // Verify the user's signature.
    let (is_valid) = IAccount.isValidSignature(admin, hash3, sig_len, sig);
    assert is_valid = TRUE;
    return ();
}
