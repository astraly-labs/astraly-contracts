%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.invoke import invoke
from starkware.cairo.common.math import (
    assert_nn_le,
    assert_not_equal,
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
)
from starkware.cairo.common.pow import pow
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_eq,
    uint256_le,
    uint256_lt,
    uint256_check,
)
from starkware.cairo.common.memcpy import memcpy
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.safemath.library import SafeUint256

from InterfaceAll import IAstralyIDOFactory, IXoroshiro, XOROSHIRO_ADDR, IERC721
from contracts.AstralyAccessControl import AstralyAccessControl
from contracts.utils.AstralyConstants import DAYS_30
from contracts.utils.Uint256_felt_conv import _felt_to_uint, _uint_to_felt
from contracts.utils import uint256_pow, get_array
from contracts.utils.Math64x61 import (
    Math64x61_fromUint256,
    Math64x61_toUint256,
    Math64x61_div,
    Math64x61_fromFelt,
    Math64x61_toFelt,
    Math64x61_mul,
    Math64x61_add,
    Math64x61__pow_int,
)

const Math64x61_BOUND_LOCAL = 2 ** 64;

struct Sale {
    // NFT being sold (interface)
    token: felt,
    // Is sale created (boolean)
    is_created: felt,
    // Are earnings withdrawn (boolean)
    raised_funds_withdrawn: felt,
    // Address of sale owner
    sale_owner: felt,
    // Price of the token quoted - needed as its the price set for the IDO
    token_price: Uint256,
    // Amount of NFTs to sell
    amount_of_tokens_to_sell: Uint256,
    // Total NFTs being sold
    total_tokens_sold: Uint256,
    // Total winning lottery tickets
    total_winning_tickets: Uint256,
    // Total Raised (what are using to track this?)
    total_raised: Uint256,
    // Sale end time
    sale_end: felt,
    // When tokens can be withdrawn
    tokens_unlock_time: felt,
    // Cap on the number of lottery tickets to burn when registring
    lottery_tickets_burn_cap: Uint256,
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
    number_of_purchases: felt,
}

struct UserRegistrationDetails {
    address: felt,
    score: felt,
}

struct UserProbability {
    address: felt,
    weight: felt,
}

// Sale
@storage_var
func sale() -> (res: Sale) {
}

// Current Token ID
@storage_var
func currentId() -> (res: Uint256) {
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

// Mapping user to number of winning lottery tickets
@storage_var
func user_to_winning_lottery_tickets(user_address: felt) -> (res: Uint256) {
}

// Mapping user to number of allocations
@storage_var
func address_to_allocations(user_address: felt) -> (res: Uint256) {
}

@storage_var
func ido_factory_contract_address() -> (res: felt) {
}

@storage_var
func ido_allocation() -> (res: Uint256) {
}

@storage_var
func users_registrations(index: felt) -> (registration_details: UserRegistrationDetails) {
}

@storage_var
func users_registrations_len() -> (length: felt) {
}

@storage_var
func user_registration_index(address: felt) -> (index: felt) {
}

@storage_var
func winners(index: felt) -> (address: UserProbability) {
}

@storage_var
func winners_len() -> (res: felt) {
}

//
// Events
//

@event
func tokens_sold(user_address: felt, amount: Uint256) {
}

@event
func user_registered(user_address: felt, winning_lottery_tickets: Uint256, amount_burnt: Uint256) {
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
func purchase_round_time_set(purchase_time_starts: felt, purchase_time_ends: felt) {
}

@event
func IDO_Created(new_ido_contract_address: felt) {
}

@event
func WinnersSelected(winners_len: felt, winners: UserProbability*) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _admin_address: felt
) {
    assert_not_zero(_admin_address);
    AstralyAccessControl.initializer(_admin_address);

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
    participation: Participation,
    tickets: Uint256,
    allocations: Uint256,
    is_registered: felt,
    has_participated: felt,
) {
    alloc_locals;
    let (_participation) = user_to_participation.read(account);
    let (_winning_tickets) = user_to_winning_lottery_tickets.read(account);
    let (_allocations) = address_to_allocations.read(account);
    let (_user_registation_index) = user_registration_index.read(account);

    if (_user_registation_index == 0) {
        return (
            participation=_participation,
            tickets=_winning_tickets,
            allocations=_allocations,
            is_registered=FALSE,
            has_participated=FALSE,
        );
    } else {
        let (participated: felt) = uint256_lt(Uint256(0, 0), _participation.amount_bought);
        return (
            participation=_participation,
            tickets=_winning_tickets,
            allocations=_allocations,
            is_registered=TRUE,
            has_participated=participated,
        );
    }
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

//############################################
// #                 INTERNALS               ##
//############################################

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

func get_adjusted_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _amount: Uint256, _cap: Uint256
) -> (res: Uint256) {
    let (is_amount_le_cap: felt) = uint256_le(_amount, _cap);
    if (is_amount_le_cap == TRUE) {
        return (res=_amount);
    } else {
        return (res=_cap);
    }
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
    _lottery_tickets_burn_cap: Uint256,
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
    with_attr error_message(
            "AstralyINOContract::set_sale_params INO Token price must be greater than zero") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), _token_price);
        assert token_price_check = TRUE;
    }
    with_attr error_message(
            "AstralyINOContract::set_sale_params Number of NFTs Tokens to sell must be greater than zero") {
        let (token_to_sell_check: felt) = uint256_lt(Uint256(0, 0), _amount_of_tokens_to_sell);
        assert token_to_sell_check = TRUE;
    }
    with_attr error_message("AstralyINOContract::set_sale_params Bad input") {
        assert_lt(block_timestamp, _sale_end_time);
    }

    // set params
    let new_sale = Sale(
        token=_token_address,
        is_created=TRUE,
        raised_funds_withdrawn=FALSE,
        sale_owner=_sale_owner_address,
        token_price=_token_price,
        amount_of_tokens_to_sell=_amount_of_tokens_to_sell,
        total_tokens_sold=Uint256(0, 0),
        total_winning_tickets=Uint256(0, 0),
        total_raised=Uint256(0, 0),
        sale_end=_sale_end_time,
        tokens_unlock_time=_tokens_unlock_time,
        lottery_tickets_burn_cap=_lottery_tickets_burn_cap,
        number_of_participants=Uint256(0, 0),
    );
    sale.write(new_sale);
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
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
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
        assert_le(block_timestamp, _registration_time_starts);
        assert_lt(_registration_time_starts, _registration_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_registration_time registration end has to be before sale end") {
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
    _purchase_time_starts: felt, _purchase_time_ends: felt
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
        assert_lt(_purchase_time_starts, _purchase_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_purchase_round_params registration time not set yet") {
        assert_not_zero(the_reg.registration_time_starts);
        assert_not_zero(the_reg.registration_time_ends);
    }
    with_attr error_message(
            "AstralyINOContract::set_purchase_round_params start time must be after registration end") {
        assert_lt(the_reg.registration_time_ends, _purchase_time_starts);
    }
    let upd_purchase = Purchase_Round(
        time_starts=_purchase_time_starts,
        time_ends=_purchase_time_ends,
        number_of_purchases=the_purchase.number_of_purchases,
    );
    purchase_round.write(upd_purchase);
    purchase_round_time_set.emit(
        purchase_time_starts=_purchase_time_starts, purchase_time_ends=_purchase_time_ends
    );
    return ();
}

@external
func register_user{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account: felt, score: felt
) -> (res: felt) {
    alloc_locals;
    let (the_reg) = registration.read();
    let (block_timestamp) = get_block_timestamp();
    let (the_sale) = sale.read();

    let (factory_address) = ido_factory_contract_address.read();
    let (lottery_ticket_address) = IAstralyIDOFactory.get_lottery_ticket_contract_address(
        contract_address=factory_address
    );
    with_attr error_message(
            "AstralyINOContract::register_user Lottery ticket contract address not set") {
        assert_not_zero(lottery_ticket_address);
    }
    let (caller) = get_caller_address();
    with_attr error_message(
            "AstralyINOContract::register_user only the lottery ticket contract can make this call") {
        assert caller = lottery_ticket_address;
    }

    with_attr error_message(
            "AstralyINOContract::register_user account address is the zero address") {
        assert_not_zero(account);
    }
    with_attr error_message("AstralyINOContract::register_user Registration window is closed") {
        assert_le(the_reg.registration_time_starts, block_timestamp);
        assert_le(block_timestamp, the_reg.registration_time_ends);
    }

    let (_user_registration_index) = user_registration_index.read(account);

    if (_user_registration_index == 0) {
        let (local registrants_sum: Uint256) = SafeUint256.add(
            the_reg.number_of_registrants, Uint256(low=1, high=0)
        );

        let upd_reg = Registration(
            registration_time_starts=the_reg.registration_time_starts,
            registration_time_ends=the_reg.registration_time_ends,
            number_of_registrants=registrants_sum,
        );
        registration.write(upd_reg);

        let (_users_registrations_len: felt) = users_registrations_len.read();
        users_registrations.write(
            _users_registrations_len, UserRegistrationDetails(account, score)
        );
        users_registrations_len.write(_users_registrations_len + 1);

        return (res=TRUE);
    }

    let (current_user_registrations_details: UserRegistrationDetails) = users_registrations.read(
        _user_registration_index
    );
    tempvar new_user_reg_score = current_user_registrations_details.score + score;
    users_registrations.write(
        _user_registration_index, UserRegistrationDetails(account, new_user_reg_score)
    );
    return (res=TRUE);
}

// This function will calculate allocation (USD/IDO Token) and will be triggered using the keeper network
@external
func calculate_allocation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();
    let (current_allocation: Uint256) = ido_allocation.read();
    with_attr error_message(
            "AstralyINOContract::calculate_allocation allocation already calculated") {
        let (allocation_check: felt) = uint256_eq(current_allocation, Uint256(0, 0));
        assert allocation_check = TRUE;
    }
    let (the_sale: Sale) = sale.read();
    local to_sell: Uint256 = the_sale.amount_of_tokens_to_sell;
    local total_winning_tickets: Uint256 = the_sale.total_winning_tickets;

    // Compute the allocation : amount_of_tokens_to_sell / total_winning_tickets
    let (the_allocation: Uint256, _) = SafeUint256.div_rem(to_sell, total_winning_tickets);
    // with_attr error_message("AstralyINOContract::calculate_allocation calculation error"):
    //     assert the_allocation * the_sale.total_winning_tickets = the_sale.amount_of_tokens_to_sell
    // end
    ido_allocation.write(the_allocation);
    allocation_computed.emit(allocation=the_allocation, sold=the_sale.amount_of_tokens_to_sell);
    return ();
}

// this function will call the VRF and determine the number of winning tickets (if any)
@view
func draw_winning_tickets{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    tickets_burnt: Uint256, score: felt, rnd: felt
) -> (res: Uint256) {
    alloc_locals;
    let (single_t: felt) = uint256_le(tickets_burnt, Uint256(1, 0));

    if (single_t == TRUE) {
        // One ticket
        let (q, r) = unsigned_div_rem(rnd, 9);
        let is_won: felt = is_le(r, 2);
        if (is_won == TRUE) {
            return (Uint256(1, 0),);
        }
        return (Uint256(0, 0),);
    }

    // Tickets_burnt * 0.6
    let (a) = Math64x61_fromFelt(3);
    let (b) = Math64x61_fromFelt(5);
    let (div) = Math64x61_div(a, b);
    let (fixed_tickets_felt) = _uint_to_felt(tickets_burnt);
    let (num1) = Math64x61_mul(fixed_tickets_felt, div);
    // score * 5
    let (num2) = Math64x61_mul(score, 5);

    // Add them
    let (sum) = Math64x61_add(num1, num2);

    // Compute rand/max
    let (rand_factor) = Math64x61_div(rnd, Math64x61_BOUND_LOCAL - 1);

    // Finally multiply both results
    let (fixed_winning) = Math64x61_mul(rand_factor, sum);
    let (winning: Uint256) = Math64x61_toUint256(fixed_winning);

    return (res=winning);
}

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

@external
func participate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount_paid: Uint256
) -> (res: felt) {
    alloc_locals;
    let (account: felt) = get_caller_address();
    let (address_this: felt) = get_contract_address();
    let (the_sale) = sale.read();
    let (block_timestamp) = get_block_timestamp();
    let (the_round) = purchase_round.read();

    // Validations
    with_attr error_message("AstralyINOContract::participate Purchase round has not started yet") {
        assert_le(the_round.time_starts, block_timestamp);
    }
    with_attr error_message("AstralyINOContract::participate Purchase round is over") {
        assert_le(block_timestamp, the_round.time_ends);
    }
    let (user_participation: Participation) = user_to_participation.read(account);
    let (user_participated: felt) = uint256_lt(Uint256(0, 0), user_participation.amount_bought);

    with_attr error_message("AstralyINOContract::participate user participated") {
        assert user_participated = FALSE;
    }
    with_attr error_message("AstralyINOContract::participate Account address is the zero address") {
        assert_not_zero(account);
    }
    with_attr error_message("AstralyINOContract::participate Amount paid is zero") {
        let (amount_paid_check: felt) = uint256_lt(Uint256(0, 0), amount_paid);
        assert amount_paid_check = TRUE;
    }
    let (the_sale) = sale.read();
    with_attr error_message("AstralyINOContract::participate the IDO token price is not set") {
        let (token_price_check: felt) = uint256_lt(Uint256(0, 0), the_sale.token_price);
        assert token_price_check = TRUE;
    }
    let (the_alloc: Uint256) = ido_allocation.read();
    with_attr error_message(
            "AstralyINOContract::participate The IDO token allocation has not been calculated") {
        let (allocation_check: felt) = uint256_lt(Uint256(0, 0), the_alloc);
        assert allocation_check = TRUE;
    }
    let (winning_tickets: Uint256) = user_to_winning_lottery_tickets.read(account);
    with_attr error_message(
            "AstralyINOContract::participate account does not have any winning lottery tickets") {
        let (winning_tkts_check: felt) = uint256_lt(Uint256(0, 0), winning_tickets);
        assert winning_tkts_check = TRUE;
    }
    let (max_tokens_to_purchase: Uint256) = SafeUint256.mul(winning_tickets, the_alloc);
    let (number_of_tokens_buying, _) = SafeUint256.div_rem(amount_paid, the_sale.token_price);
    with_attr error_message(
            "AstralyINOContract::participate Can't buy more than maximum allocation") {
        let (is_tokens_buying_le_max) = uint256_le(number_of_tokens_buying, max_tokens_to_purchase);
        assert is_tokens_buying_le_max = TRUE;
    }

    // Updates

    let (local total_tokens_sum: Uint256) = SafeUint256.add(
        the_sale.total_tokens_sold, number_of_tokens_buying
    );

    let (local total_raised_sum: Uint256) = SafeUint256.add(the_sale.total_raised, amount_paid);
    let (local number_of_participants_sum: Uint256) = SafeUint256.add(
        the_sale.number_of_participants, Uint256(1, 0)
    );

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=total_tokens_sum,
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=total_raised_sum,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=number_of_participants_sum,
    );
    sale.write(upd_sale);

    let new_purchase = Participation(
        amount_bought=number_of_tokens_buying,
        amount_paid=amount_paid,
        time_participated=block_timestamp,
        claimed=FALSE,
    );
    user_to_participation.write(account, new_purchase);

    let (factory_address) = ido_factory_contract_address.read();
    let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
        contract_address=factory_address
    );
    with_attr error_message("AstralyINOContract::participate Payment token address not set") {
        assert_not_zero(pmt_token_addr);
    }
    let (pmt_success: felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, amount_paid
    );
    with_attr error_message("AstralyINOContract::participate Participation payment failed") {
        assert pmt_success = TRUE;
    }
    let new_number_of_purchases: felt = the_round.number_of_purchases + 1;
    let upd_purchase = Purchase_Round(
        time_starts=the_round.time_starts,
        time_ends=the_round.time_ends,
        number_of_purchases=new_number_of_purchases,
    );
    purchase_round.write(upd_purchase);
    tokens_sold.emit(user_address=account, amount=number_of_tokens_buying);
    return (res=TRUE);
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
        assert_le(the_sale.tokens_unlock_time, block_timestamp);
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
        let token_address = the_sale.token;
        let (current_id: Uint256) = currentId.read();
        IERC721.mint(token_address, address_caller, participation.amount_bought);
        let (new_id: Uint256) = SafeUint256.add(current_id, participation.amount_bought);
        currentId.write(new_id);
        tokens_withdrawn.emit(user_address=address_caller, amount=participation.amount_bought);
        return ();
    }
    return ();
}

@external
func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    AstralyAccessControl.assert_only_owner();
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
    with_attr error_message(
            "AstralyIDOContract::withdraw_multiple_portions token transfer failed") {
        assert token_transfer_success = TRUE;
    }

    let (the_sale) = sale.read();
    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=TRUE,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);
    return ();
}

@external
func selectWinners{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    start_index: felt, end_index: felt, no_of_winners_per_curr_batch : felt
) -> (winners_array_len: felt, winners_array: UserProbability*) {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();

    with_attr error_message("AstralyINOContract::selectKelements invalid end index") {
        assert_lt(start_index, end_index);
    }

    let (block_timestamp) = get_block_timestamp();
    let (the_reg) = registration.read();
    with_attr error_message(
            "AstralyINOContract::get_winning_tickets Registration window is not closed") {
        assert_le(the_reg.registration_time_ends, block_timestamp);
    }

    tempvar array_len = 1 + end_index - start_index;
    let (user_reg_len: felt) = users_registrations_len.read();

    with_attr error_message("AstralyINOContract::selectKelements no registered users") {
        assert_not_zero(user_reg_len);
    }
    with_attr error_message(
            "AstralyINOContract::selectKelements current batch size larger than number of users") {
        assert_le(array_len, user_reg_len);
    }
    let (ido_factory_address) = ido_factory_contract_address.read();
    let (rnd_nbr_gen_addr) = IAstralyIDOFactory.get_random_number_generator_address(
        ido_factory_address
    );
    with_attr error_message(
            "AstralyINOContract::selectKelements random number generator address not set in the factory") {
        assert_not_zero(rnd_nbr_gen_addr);
    }

    let (allocation_arr: UserProbability*) = alloc();
    let (allocation_arr_sorted: UserProbability*) = alloc();

    get_users_registration_array(start_index, end_index, 0, allocation_arr, rnd_nbr_gen_addr);

    sort_recursive(array_len, allocation_arr, 0, allocation_arr_sorted);

    let (the_sale: Sale) = sale.read();

    let (winners_array: UserProbability*) = alloc();

    memcpy(
        winners_array, allocation_arr_sorted, no_of_winners_per_curr_batch * UserProbability.SIZE
    );

    let (no_of_winners_per_curr_batch_uint: Uint256) = _felt_to_uint(no_of_winners_per_curr_batch);
    let (total_winning_tickets_sum: Uint256) = SafeUint256.add(
        the_sale.total_winning_tickets, no_of_winners_per_curr_batch_uint
    );

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        sale_owner=the_sale.sale_owner,
        token_price=the_sale.token_price,
        amount_of_tokens_to_sell=the_sale.amount_of_tokens_to_sell,
        total_tokens_sold=the_sale.total_tokens_sold,
        total_winning_tickets=total_winning_tickets_sum,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=the_sale.number_of_participants,
    );
    sale.write(upd_sale);

    WinnersSelected.emit(no_of_winners_per_curr_batch, winners_array);

    let (current_winners_len: felt) = winners_len.read();
    add_winners_rec(0, no_of_winners_per_curr_batch, winners_array, current_winners_len);

    return (no_of_winners_per_curr_batch, winners_array);
}

@view
func getWinnersArray{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    arr_len: felt, arr: UserProbability*
) {
    alloc_locals;
    let (mapping_ref: felt*) = get_label_location(winners.read);
    let (len: felt) = winners_len.read();

    let (arr: UserProbability*) = alloc();
    get_winners_rec(len, arr, mapping_ref);

    return (len, arr);
}

func get_winners_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: UserProbability*, mapping_ref: felt*
) {
    if (array_len == 0) {
        return ();
    }
    let index = array_len - 1;
    tempvar args: felt* = cast(new (syscall_ptr, pedersen_ptr, range_check_ptr, index), felt*);
    invoke(mapping_ref, 4, args);
    let syscall_ptr = cast([ap - 5], felt*);
    let pedersen_ptr = cast([ap - 4], HashBuiltin*);
    let range_check_ptr = [ap - 3];
    assert array[index] = UserProbability([ap - 2], [ap - 1]);

    return get_winners_rec(array_len - 1, array, mapping_ref);
}

func add_winners_rec{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt,
    no_of_winners_per_curr_batch: felt,
    winners_array: UserProbability*,
    current_winners_len: felt,
) {
    if (no_of_winners_per_curr_batch == index) {
        winners_len.write(current_winners_len);
        return ();
    }
    winners.write(current_winners_len, winners_array[index]);

    return add_winners_rec(
        index + 1, no_of_winners_per_curr_batch, winners_array, current_winners_len + 1
    );
}

func sort_recursive{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    old_arr_len: felt, old_arr: UserProbability*, sorted_arr_len: felt, sorted_arr: UserProbability*
) {
    alloc_locals;
    if (old_arr_len == 0) {
        return ();
    }
    let indexOfMax: felt = index_of_max(old_arr_len, old_arr);
    // Pushing the max occurence to the last available spot
    assert sorted_arr[sorted_arr_len] = old_arr[indexOfMax];
    // getting a new old array
    let (old_shortened_arr_len, old_shortened_arr) = remove_at(old_arr_len, old_arr, indexOfMax);
    return sort_recursive(old_shortened_arr_len, old_shortened_arr, sorted_arr_len + 1, sorted_arr);
}

func remove_at{pedersen_ptr: HashBuiltin*, range_check_ptr}(
    arr_len: felt, arr: UserProbability*, index: felt
) -> (new_arr_len: felt, new_arr: UserProbability*) {
    alloc_locals;

    assert_lt(index, arr_len);
    let (new_arr: UserProbability*) = alloc();
    memcpy(new_arr, arr, index * UserProbability.SIZE);
    tempvar slots = index * UserProbability.SIZE;
    tempvar struct_arr_len = arr_len * UserProbability.SIZE;
    memcpy(
        new_arr + slots,
        arr + slots + UserProbability.SIZE,
        struct_arr_len - slots - UserProbability.SIZE,
    );
    return (arr_len - 1, new_arr);
}

func get_users_registration_array{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    index: felt, end_index: felt, array_len: felt, array: UserProbability*, rnd_nbr_gen_addr: felt
) {
    alloc_locals;
    if (index == end_index + 1) {
        return ();
    }
    let (rnd: felt) = IXoroshiro.next(rnd_nbr_gen_addr);
    let (_user_reg_details: UserRegistrationDetails) = users_registrations.read(index);

    let (weight: felt) = pow(_user_reg_details.score, rnd);
    let user_prob_struct: UserProbability = UserProbability(_user_reg_details.address, weight);

    assert array[array_len] = user_prob_struct;
    return get_users_registration_array(
        index + 1, end_index, array_len + 1, array, rnd_nbr_gen_addr
    );
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
    let isLe = is_le(current_max, arr[current_index].weight);
    if (isLe == TRUE) {
        return index_of_max_recursive(
            arr_len, arr, arr[current_index].weight, current_index, current_index + 1
        );
    }
    return index_of_max_recursive(arr_len, arr, current_max, current_max_index, current_index + 1);
}
