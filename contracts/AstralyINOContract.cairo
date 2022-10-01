%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import (
    assert_nn_le,
    assert_not_equal,
    assert_not_zero,
    assert_le_felt,
    assert_lt_felt,
    unsigned_div_rem,
)
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.memcpy import memcpy
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
from InterfaceAll import IAstralyIDOFactory, IXoroshiro, XOROSHIRO_ADDR, IAccount, IERC721

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
    claimed: felt,
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

struct UserRegistrationDetails {
    address: felt,
    score: felt,
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

@storage_var
func ido_factory_contract_address() -> (res: felt) {
}

@storage_var
func admin_address() -> (res: felt) {
}

@storage_var
func ido_allocation() -> (res: Uint256) {
}

@storage_var
func users_registrations(i: felt) -> (res: UserRegistrationDetails) {
}

@storage_var
func users_registrations_len() -> (res: felt) {
}

@storage_var
func participants(user_address: felt) -> (res: felt) {
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
func INO_Created(new_ino_contract_address: felt) {
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
    INO_Created.emit(address_this);
    return ();
}

//############################################
// #                 GETTERS                 ##
//############################################

@view
func get_ino_launch_date{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
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
func get_allocation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user: felt
) -> (res: felt) {
    let (allocation) = participants.read(user);
    return (res=allocation);
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
    alloc_locals;
    AstralyAccessControl.assert_only_owner();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    with_attr error_message("AstralyINOContract::set_sale_params Sale is already created") {
        assert the_sale.is_created = FALSE;
    }
    with_attr error_message("AstralyINOContract::set_sale_params Sale owner address can not be 0") {
        assert_not_zero(_sale_owner_address);
    }
    with_attr error_message("AstralyINOContract::set_sale_params Token address can not be 0") {
        assert_not_zero(_token_address);
    }
    with_attr error_message(
            "AstralyINOContract::set_sale_params IDO Token price must be greater than zero") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), _token_price);
        assert token_price_check = TRUE;
    }
    with_attr error_message(
            "AstralyINOContract::set_sale_params Number of IDO Tokens to sell must be greater than zero") {
        let (token_to_sell_check: felt) = uint256_lt(Uint256(0, 0), _amount_of_tokens_to_sell);
        assert token_to_sell_check = TRUE;
    }
    with_attr error_message("AstralyINOContract::set_sale_params Sale end time in the past") {
        assert_lt_felt(block_timestamp, _sale_end_time);
    }
    with_attr error_message("AstralyINOContract::set_sale_params Tokens unlock time in the past") {
        assert_lt_felt(block_timestamp, _tokens_unlock_time);
    }

    // set params
    let new_sale = Sale(
        token=_token_address,
        is_created=TRUE,
        raised_funds_withdrawn=FALSE,
        leftover_withdrawn=FALSE,
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
    with_attr error_message("AstralyINOContract::set_registration_time Sale not created yet") {
        assert the_sale.is_created = TRUE;
    }
    // with_attr error_message(
    //         "AstralyINOContract::set_registration_time the registration start time is already set"):
    //     assert the_reg.registration_time_starts = 0
    // end
    with_attr error_message(
            "AstralyINOContract::set_registration_time registration start/end times issue") {
        assert_le_felt(block_timestamp, _registration_time_starts);
        assert_lt_felt(_registration_time_starts, _registration_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_registration_time registration end has to be before sale end") {
        assert_lt_felt(_registration_time_ends, the_sale.sale_end);
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
    with_attr error_message("AstralyINOContract::set_purchase_round_params Bad input") {
        assert_not_zero(_purchase_time_starts);
        assert_not_zero(_purchase_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_purchase_round_params end time must be after start end") {
        assert_lt_felt(_purchase_time_starts, _purchase_time_ends);
    }
    with_attr error_message("AstralyINOContract::max_participation must be non-null") {
        let (participation_check: felt) = uint256_lt(Uint256(0, 0), max_participation);
        assert participation_check = TRUE;
    }
    with_attr error_message(
            "AstralyINOContract::set_purchase_round_params registration time not set yet") {
        assert_not_zero(the_reg.registration_time_starts);
        assert_not_zero(the_reg.registration_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_purchase_round_params start time must be after registration end") {
        assert_lt_felt(the_reg.registration_time_ends, _purchase_time_starts);
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

    with_attr error_message("AstralyINOContract::register_user Registration window is closed") {
        assert_le_felt(the_reg.registration_time_starts, block_timestamp);
        assert_le_felt(block_timestamp, the_reg.registration_time_ends);
    }
    with_attr error_message("AstralyINOContract::register_user invalid signature") {
        check_registration_signature(signature_len, signature, signature_expiration, caller);
    }
    with_attr error_message("AstralyINOContract::register_user signature expired") {
        assert_lt_felt(block_timestamp, signature_expiration);
    }
    let (is_user_reg) = is_registered.read(caller);
    with_attr error_message("AstralyINOContract::register_user user already registered") {
        assert is_user_reg = FALSE;
    }

    // Save user registration
    is_registered.write(caller, TRUE);
    // Add to registrants array
    let (local registrants_len) = users_registrations_len.read();
    // TODO: get the score
    let score = 0;
    users_registrations.write(registrants_len, UserRegistrationDetails(caller, score));
    users_registrations_len.write(registrants_len + 1);
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
}(amount_paid: Uint256, test: Uint256, sig_len: felt, sig: felt*) {
    alloc_locals;
    let (account: felt) = get_caller_address();
    let (the_round) = purchase_round.read();
    let (block_timestamp) = get_block_timestamp();

    // with_attr error_message("AstralyINOContract::participate invalid signature") {
    //     check_participation_signature(sig_len, sig, account, amount);
    // }
    with_attr error_message("AstralyINOContract::participate Purchase round has not started yet") {
        assert_le_felt(the_round.time_starts, block_timestamp);
    }
    with_attr error_message("AstralyINOContract::participate Purchase round is over") {
        assert_le_felt(block_timestamp, the_round.time_ends);
    }
    let (allocation) = participants.read(account);
    with_attr error_message("AstralyINOContract::participate no allocation") {
        assert_lt_felt(0, allocation);
    }
    // let (allocation_uint) = _felt_to_uint(allocation);
    // let (amount) = SafeUint256.mul(allocation_uint, smth?);
    // TODO: compute allocation amount
    _participate(account, amount_paid, the_round.max_participation, block_timestamp, the_round);
    return ();
}

func _participate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account: felt,
    amount_paid: Uint256,
    amount: Uint256,
    block_timestamp: felt,
    the_round: Purchase_Round,
) {
    alloc_locals;
    let (address_this: felt) = get_contract_address();

    // Validations
    with_attr error_message("AstralyINOContract::participate Crossing max participation") {
        let (amount_check: felt) = uint256_le(amount, the_round.max_participation);
        assert amount_check = TRUE;
    }
    // with_attr error_message("AstralyINOContract::participate User not registered") {
    //     let (_is_registered) = is_registered.read(account);
    //     assert _is_registered = TRUE;
    // }
    with_attr error_message("AstralyINOContract::participate Purchase round has not started yet") {
        assert_le_felt(the_round.time_starts, block_timestamp);
    }
    let (user_participated) = has_participated.read(account);
    with_attr error_message("AstralyINOContract::participate user participated") {
        assert user_participated = FALSE;
    }
    with_attr error_message("AstralyINOContract::participate Purchase round is over") {
        assert_le_felt(block_timestamp, the_round.time_ends);
    }

    // with_attr error_message("AstralyINOContract::participate Account address is the zero address") {
    //     assert_not_zero(account);
    // }
    // with_attr error_message("AstralyINOContract::participate Amount paid is zero") {
    //     let (amount_paid_check: felt) = uint256_lt(Uint256(0, 0), amount_paid);
    //     assert amount_paid_check = TRUE;
    // }

    let (the_sale) = sale.read();
    with_attr error_message("AstralyINOContract::participate the IDO token price is not set") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), the_sale.token_price);
        assert token_price_check = TRUE;
    }

    let (factory_address) = ido_factory_contract_address.read();
    let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
        contract_address=factory_address
    );
    with_attr error_message("AstralyINOContract::participate Payment token address not set") {
        assert_not_zero(pmt_token_addr);
    }

    let (number_of_tokens_buying_mod, _) = SafeUint256.div_rem(amount_paid, the_sale.token_price);

    // Must buy more than 0 tokens
    with_attr error_message("AstralyINOContract::participate Can't buy 0 tokens") {
        let (is_tokens_buying_valid: felt) = uint256_lt(Uint256(0, 0), number_of_tokens_buying_mod);
        assert is_tokens_buying_valid = TRUE;
    }

    // Check user allocation
    with_attr error_message("AstralyINOContract::participate Exceeding allowance") {
        let (valid_allocation: felt) = uint256_le(number_of_tokens_buying_mod, amount);
        assert valid_allocation = TRUE;
    }

    // Require that amountOfTokensBuying is less than sale token leftover cap
    with_attr error_message("AstralyINOContract::participate Not enough tokens to sell") {
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
        claimed=0,
    );
    user_to_participation.write(account, new_purchase);

    has_participated.write(account, TRUE);

    // Only take the correct amount
    let (pmt_amount) = SafeUint256.mul(number_of_tokens_buying_mod, the_sale.token_price);
    let (pmt_success: felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, pmt_amount
    );
    with_attr error_message("AstralyINOContract::participate Participation payment failed") {
        assert pmt_success = TRUE;
    }
    tokens_sold.emit(user_address=account, amount=number_of_tokens_buying_mod);
    return ();
}

@storage_var
func currentId() -> (res: Uint256) {
}

@external
func withdraw_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    let (address_caller: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    let (participation) = user_to_participation.read(address_caller);

    with_attr error_message("AstralyINOContract::withdraw_tokens Tokens can not be withdrawn yet") {
        assert_le_felt(the_sale.tokens_unlock_time, block_timestamp);
    }

    with_attr error_message("AstralyINOContract::already claimed") {
        assert participation.claimed = FALSE;
    }

    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        claimed=TRUE,
    );
    user_to_participation.write(address_caller, participation_upd);

    let (amt_withdrawing_check: felt) = uint256_lt(Uint256(0, 0), participation.amount_bought);

    if (amt_withdrawing_check == TRUE) {
        let (current_id: Uint256) = currentId.read();
        batch_mint(the_sale.token, address_caller, current_id, participation.amount_bought);
        let (new_id: Uint256) = SafeUint256.add(current_id, participation.amount_bought);
        currentId.write(new_id);
        tokens_withdrawn.emit(user_address=address_caller, amount=participation.amount_bought);
        return ();
    } else {
        return ();
    }
}

@external
func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (address_caller: felt) = get_caller_address();
    let (factory_address) = ido_factory_contract_address.read();
    let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
        contract_address=factory_address
    );
    let (the_sale) = sale.read();

    with_attr error_message(
            "AstralyINOContract::withdraw_from_contract raised funds already withdrawn") {
        assert the_sale.raised_funds_withdrawn = FALSE;
    }

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=TRUE,
        leftover_withdrawn=the_sale.leftover_withdrawn,
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

    let (token_transfer_success: felt) = IERC20.transfer(
        pmt_token_addr, address_caller, the_sale.total_raised
    );
    with_attr error_message("AstralyINOContract::withdraw_from_contract token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    return ();
}

@external
func withdraw_leftovers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_role(SALE_OWNER_ROLE);
    let (address_caller: felt) = get_caller_address();
    let (the_sale) = sale.read();

    let (block_timestamp) = get_block_timestamp();

    with_attr error_message("AstralyINOContract::withdraw_leftovers sale not ended") {
        assert_le_felt(the_sale.sale_end, block_timestamp);
    }

    with_attr error_message("AstralyINOContract::withdraw_leftovers leftovers already withdrawn") {
        assert the_sale.leftover_withdrawn = FALSE;
    }

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=TRUE,
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

    let (leftover) = SafeUint256.sub_le(
        the_sale.amount_of_tokens_to_sell, the_sale.total_tokens_sold
    );
    let (token_transfer_success: felt) = IERC20.transfer(the_sale.token, address_caller, leftover);
    with_attr error_message("AstralyINOContract::withdraw_leftovers token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    return ();
}

//############################################
// #                 INTERNALS              ##
//############################################

func get_random_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    rnd: felt
) {
    let (ido_factory_address) = ido_factory_contract_address.read();
    let (rnd_nbr_gen_addr) = IAstralyIDOFactory.get_random_number_generator_address(
        contract_address=ido_factory_address
    );
    with_attr error_message(
            "AstralyINOContract::get_random_number random number generator address not set in the factory") {
        assert_not_zero(rnd_nbr_gen_addr);
    }
    let (rnd_felt) = IXoroshiro.next(contract_address=rnd_nbr_gen_addr);
    with_attr error_message("AstralyINOContract::get_random_number invalid random number value") {
        assert_not_zero(rnd_felt);
    }
    return (rnd=rnd_felt);
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

struct UserProbability {
    address: felt,
    weight: felt,
}

@event
func WinnersSelected(winners_len: felt, winners: felt*) {
}

@storage_var
func last_index_processed() -> (res: felt) {
}

@external
func selectWinners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    start_index: felt, end_index: felt, batch_size: felt
) -> (winners_array_len: felt, winners_array: felt*) {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();

    let (_last_index_processed: felt) = last_index_processed.read();

    with_attr error_message("AstralyINOContract::selectKelements indexes already proccesed") {
        assert_le_felt(_last_index_processed, start_index);
        last_index_processed.write(end_index);
    }

    with_attr error_message("AstralyINOContract::selectKelements invalid end index") {
        assert_le_felt(start_index, end_index);
    }

    let (block_timestamp) = get_block_timestamp();
    let (the_reg) = registration.read();
    with_attr error_message(
            "AstralyINOContract::get_winning_tickets Registration window is not closed") {
        assert_le_felt(the_reg.registration_time_ends, block_timestamp);
    }

    tempvar array_len = 1 + end_index - start_index;
    let (user_reg_len: felt) = users_registrations_len.read();

    with_attr error_message("AstralyINOContract::selectKelements no registered users") {
        assert_not_zero(user_reg_len);
    }
    with_attr error_message(
            "AstralyINOContract::selectKelements current batch size larger than number of users") {
        assert_le_felt(array_len, user_reg_len);
    }
    let (ido_factory_address) = ido_factory_contract_address.read();
    let (rnd_nbr_gen_addr) = IAstralyIDOFactory.get_random_number_generator_address(
        ido_factory_address
    );
    with_attr error_message(
            "AstralyINOContract::selectKelements random number generator address not set in the factory") {
        assert_not_zero(rnd_nbr_gen_addr);
    }

    let (allocation_arr: UserRegistrationDetails*) = alloc();

    get_users_registration_array(start_index, end_index, 0, allocation_arr);

    let winners_array: felt* = draw_winners(
        array_len, allocation_arr, batch_size, rnd_nbr_gen_addr
    );

    WinnersSelected.emit(batch_size, winners_array);
    return (winners_array_len=batch_size, winners_array=winners_array);
}

func draw_winners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt,
    allocation_arr: UserRegistrationDetails*,
    batch_size: felt,
    rnd_nbr_gen_addr: felt,
) -> felt* {
    alloc_locals;
    let (winners_array: felt*) = alloc();

    draw_winners_rec(array_len, allocation_arr, winners_array, 0, batch_size, rnd_nbr_gen_addr);

    return (winners_array);
}

func draw_winners_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt,
    allocation_arr: UserRegistrationDetails*,
    winners_arr: felt*,
    winners_alloc_index: felt,
    batch_size: felt,
    rnd_nbr_gen_addr: felt,
) {
    alloc_locals;
    if (winners_alloc_index == batch_size) {
        return ();
    }

    let (user_weights: UserProbability*) = alloc();
    get_user_weights_rec(user_weights, 0, array_len, allocation_arr, rnd_nbr_gen_addr);

    let winner_index: felt = index_of_max(array_len, user_weights);

    let (counter) = participants.read(user_weights[winner_index].address);
    participants.write(user_weights[winner_index].address, counter + 1);

    assert winners_arr[winners_alloc_index] = user_weights[winner_index].address;

    return draw_winners_rec(
        array_len,
        allocation_arr,
        winners_arr,
        winners_alloc_index + 1,
        batch_size,
        rnd_nbr_gen_addr,
    );
}

func get_user_weights_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_weights_arr: UserProbability*,
    index: felt,
    allocation_len: felt,
    allocation_arr: UserRegistrationDetails*,
    rnd_nbr_gen_addr: felt,
) {
    alloc_locals;

    if (index == allocation_len) {
        return ();
    }
    let (rnd: felt) = IXoroshiro.next(rnd_nbr_gen_addr);
    let (weight: felt) = pow(allocation_arr[index].score, rnd);

    let user_prob_struct: UserProbability = UserProbability(allocation_arr[index].address, weight);

    assert user_weights_arr[index] = user_prob_struct;

    return get_user_weights_rec(
        user_weights_arr, index + 1, allocation_len, allocation_arr, rnd_nbr_gen_addr
    );
}

func get_users_registration_array{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt, end_index: felt, array_len: felt, array: UserRegistrationDetails*
) {
    alloc_locals;
    if (index == end_index + 1) {
        return ();
    }

    let (_user_reg_details: UserRegistrationDetails) = users_registrations.read(index);

    assert array[array_len] = _user_reg_details;
    return get_users_registration_array(index + 1, end_index, array_len + 1, array);
}

func index_of_max{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    arr_len: felt, arr: UserProbability*
) -> felt {
    return index_of_max_recursive(arr_len, arr, arr[0].weight, 0, 1);
}

func index_of_max_recursive{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    arr_len: felt,
    arr: UserProbability*,
    current_max: felt,
    current_max_index: felt,
    current_index: felt,
) -> felt {
    if (arr_len == current_index) {
        return (current_max_index);
    }
    let isLe = is_le_felt(current_max, arr[current_index].weight);
    if (isLe == TRUE) {
        return index_of_max_recursive(
            arr_len, arr, arr[current_index].weight, current_index, current_index + 1
        );
    }
    return index_of_max_recursive(arr_len, arr, current_max, current_max_index, current_index + 1);
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

// MOCKING

@external
func set_user_registration_mock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: UserRegistrationDetails*
) {
    assert_not_zero(array_len);
    write_rec(array_len - 1, array);

    users_registrations_len.write(array_len);
    return ();
}

func write_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt, array: UserRegistrationDetails*
) {
    users_registrations.write(index, array[index]);
    if (index == 0) {
        return ();
    }

    return write_rec(index - 1, array);
}
