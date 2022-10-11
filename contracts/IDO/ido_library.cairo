%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_lt, uint256_eq
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_lt_felt,
    assert_le_felt,
    unsigned_div_rem,
)
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.pow import pow
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.security.safemath.library import SafeUint256
from openzeppelin.token.erc20.IERC20 import IERC20

from InterfaceAll import IAstralyIDOFactory, IXoroshiro, IAccount
from contracts.utils import uint256_is_zero, is_lt

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

struct PurchaseRound {
    time_starts: felt,
    time_ends: felt,
    max_participation: Uint256,
}

struct DistributionRound {
    time_starts: felt,
}

struct UserRegistrationDetails {
    address: felt,
    score: felt,
}

//
// Storage variables
//

// Sale
@storage_var
func IDO_sale() -> (res: Sale) {
}

// Registration
@storage_var
func IDO_registration() -> (res: Registration) {
}

@storage_var
func IDO_purchase_round() -> (res: PurchaseRound) {
}

// Mapping user to his participation
@storage_var
func IDO_user_to_participation(user_address: felt) -> (res: Participation) {
}

// Mapping user to number of allocations
@storage_var
func IDO_address_to_allocations(user_address: felt) -> (res: Uint256) {
}

// total allocations given
@storage_var
func IDO_total_allocations_given() -> (res: Uint256) {
}

@storage_var
func IDO_ido_factory_contract_address() -> (res: felt) {
}

@storage_var
func IDO_admin_address() -> (res: felt) {
}

@storage_var
func IDO_users_registrations(index: felt) -> (res: UserRegistrationDetails) {
}

@storage_var
func IDO_users_registrations_len() -> (res: felt) {
}

@storage_var
func IDO_user_registration_index(address: felt) -> (index: felt) {
}

@storage_var
func IDO_winners_arr(index: felt) -> (res: UserRegistrationDetails) {
}

@storage_var
func IDO_winners_arr_len() -> (res: felt) {
}

@storage_var
func IDO_winners(address: felt) -> (count: felt) {
}

@storage_var
func IDO_max_winners_len() -> (max_len: felt) {
}

@storage_var
func IDO_participants(user_address: felt) -> (res: felt) {
}

//
// Events
//
@event
func TokensSold(user_address: felt, amount: Uint256) {
}

@event
func UserRegistered(user_address: felt) {
}

@event
func TokenPriceSet(new_price: Uint256) {
}

@event
func AllocationComputed(allocation: Uint256, sold: Uint256) {
}

@event
func TokensWithdrawn(user_address: felt, amount: Uint256) {
}

@event
func SaleCreated(
    sale_owner_address: felt,
    token_price: Uint256,
    amount_of_tokens_to_sell: Uint256,
    sale_end: felt,
    tokens_unlock_time: felt,
) {
}

@event
func RegistrationTimeSet(registration_time_starts: felt, registration_time_ends: felt) {
}

@event
func PurchaseRoundSet(
    purchase_time_starts: felt, purchase_time_ends: felt, max_participation: Uint256
) {
}

namespace IDO {
    func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(admin: felt) {
        assert_not_zero(admin);
        IDO_admin_address.write(admin);

        let (caller: felt) = get_caller_address();
        IDO_ido_factory_contract_address.write(caller);

        return ();
    }

    func get_ido_launch_date{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: felt
    ) {
        let (the_reg) = IDO_registration.read();
        return (res=the_reg.registration_time_starts);
    }

    func get_current_sale{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: Sale
    ) {
        return IDO_sale.read();
    }

    func get_user_info{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        account: felt
    ) -> (
        participation: Participation,
        allocations: Uint256,
        is_registered: felt,
        has_participated: felt,
    ) {
        alloc_locals;
        let (participation: Participation) = IDO_user_to_participation.read(account);
        let (allocations: Uint256) = IDO_address_to_allocations.read(account);
        let is_user_registered = is_registered(account);
        let has_participated = have_user_participated(account);

        // TODO: get value
        return (
            participation=participation,
            allocations=allocations,
            is_registered=is_user_registered,
            has_participated=has_participated,
        );
    }

    func get_user_participation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        account: felt
    ) -> Participation {
        let (participation: Participation) = IDO_user_to_participation.read(account);
        return (participation);
    }

    func get_purchase_round{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: PurchaseRound
    ) {
        let (round) = IDO_purchase_round.read();
        return (res=round);
    }

    func get_registration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: Registration
    ) {
        let (_registration) = IDO_registration.read();
        return (res=_registration);
    }

    func get_allocation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) -> felt {
        with_attr error_message(
                "get_allocation::Registration window not closed") {
            let (the_reg) = IDO_registration.read();
            let (block_timestamp) = get_block_timestamp();
            assert_lt_felt(the_reg.registration_time_ends, block_timestamp);
        }

        let (count: felt) = IDO_winners.read(address);
        return (count);
    }

    func get_max_winners_len{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        res: felt
    ) {
        let (max_len) = IDO_max_winners_len.read();
        return (res=max_len);
    }

    func is_registered{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) -> felt {
        let (user_reg_index: felt) = IDO_user_registration_index.read(address);
        let (user_reg_details: UserRegistrationDetails) = IDO_users_registrations.read(
            user_reg_index
        );
        if (user_reg_details.address == 0) {
            return FALSE;
        }
        return TRUE;
    }

    func have_user_participated{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) -> felt {
        alloc_locals;
        let (user_participation: Participation) = IDO_user_to_participation.read(address);
        let res: felt = uint256_is_zero(user_participation.amount_bought);
        return (res);
    }

    func set_max_winners_len{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        max_len: felt
    ) {
        IDO_max_winners_len.write(max_len);
        return ();
    }

    func set_user_participation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        account: felt, participation: Participation
    ) {
        IDO_user_to_participation.write(account, participation);
        return ();
    }

    func set_purchase_round_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _purchase_time_starts: felt, _purchase_time_ends: felt, max_participation: Uint256
    ) {
        let (the_reg) = get_registration();
        let (the_purchase) = get_purchase_round();
        with_attr error_message("set_purchase_round_params::Bad input") {
            assert_not_zero(_purchase_time_starts);
            assert_not_zero(_purchase_time_ends);
        }
        with_attr error_message(
                "set_purchase_round_params::End time must be after start end") {
            assert_lt_felt(_purchase_time_starts, _purchase_time_ends);
        }
        with_attr error_message("set_purchase_round_params::Must be non-null") {
            let (participation_check: felt) = uint256_lt(Uint256(0, 0), max_participation);
            assert participation_check = TRUE;
        }
        with_attr error_message(
                "set_purchase_round_params::Registration time not set yet") {
            assert_not_zero(the_reg.registration_time_starts);
            assert_not_zero(the_reg.registration_time_ends);
        }
        with_attr error_message(
                "set_purchase_round_params::Start time must be after registration end") {
            assert_lt_felt(the_reg.registration_time_ends, _purchase_time_starts);
        }
        let upd_purchase = PurchaseRound(
            time_starts=_purchase_time_starts,
            time_ends=_purchase_time_ends,
            max_participation=max_participation,
        );
        IDO_purchase_round.write(upd_purchase);
        PurchaseRoundSet.emit(
            purchase_time_starts=_purchase_time_starts,
            purchase_time_ends=_purchase_time_ends,
            max_participation=max_participation,
        );
        return ();
    }

    func set_sale_params{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _token_address: felt,
        _sale_owner_address: felt,
        _token_price: Uint256,
        _amount_of_tokens_to_sell: Uint256,
        _sale_end_time: felt,
        _tokens_unlock_time: felt,
    ) {
        alloc_locals;
        let (the_sale) = get_current_sale();
        let (block_timestamp) = get_block_timestamp();
        with_attr error_message("set_sale_params::Sale is already created") {
            assert the_sale.is_created = FALSE;
        }
        with_attr error_message(
                "set_sale_params::Sale owner address can not be 0") {
            assert_not_zero(_sale_owner_address);
        }
        with_attr error_message("set_sale_params::Token address can not be 0") {
            assert_not_zero(_token_address);
        }
        with_attr error_message(
                "set_sale_params::IDO Token price must be greater than zero") {
            let (token_price_check: felt) = uint256_lt(Uint256(0, 0), _token_price);
            assert token_price_check = TRUE;
        }
        with_attr error_message(
                "set_sale_params::Number of IDO Tokens to sell must be greater than zero") {
            let (token_to_sell_check: felt) = uint256_lt(Uint256(0, 0), _amount_of_tokens_to_sell);
            assert token_to_sell_check = TRUE;
        }
        with_attr error_message("set_sale_params::Sale end time in the past") {
            assert_lt_felt(block_timestamp, _sale_end_time);
        }
        with_attr error_message(
                "set_sale_params::Tokens unlock time in the past") {
            assert_lt_felt(block_timestamp, _tokens_unlock_time);
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
        IDO_sale.write(new_sale);
        // Set portion vesting precision
        // emit event
        SaleCreated.emit(
            sale_owner_address=_sale_owner_address,
            token_price=_token_price,
            amount_of_tokens_to_sell=_amount_of_tokens_to_sell,
            sale_end=_sale_end_time,
            tokens_unlock_time=_tokens_unlock_time,
        );
        return ();
    }

    func set_sale_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _sale_token_address: felt
    ) {
        let (the_sale) = get_current_sale();
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
        IDO_sale.write(upd_sale);
        return ();
    }

    func set_registration_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _registration_time_starts: felt, _registration_time_ends: felt
    ) {
        let (the_sale) = get_current_sale();
        let (the_reg) = get_registration();
        let (block_timestamp) = get_block_timestamp();
        with_attr error_message("set_registration_time::Sale not created yet") {
            assert the_sale.is_created = TRUE;
        }
        // with_attr error_message(
        //         "set_registration_time::The registration start time is already set"):
        //     assert the_reg.registration_time_starts = 0
        // end
        with_attr error_message(
                "set_registration_time::Registration start/end times issue") {
            assert_le_felt(block_timestamp, _registration_time_starts);
            assert_lt_felt(_registration_time_starts, _registration_time_ends);
        }
        with_attr error_message(
                "set_registration_time::Registration end has to be before sale end") {
            assert_lt_felt(_registration_time_ends, the_sale.sale_end);
        }
        let upd_reg = Registration(
            registration_time_starts=_registration_time_starts,
            registration_time_ends=_registration_time_ends,
            number_of_registrants=the_reg.number_of_registrants,
        );
        IDO_registration.write(upd_reg);
        RegistrationTimeSet.emit(
            registration_time_starts=_registration_time_starts,
            registration_time_ends=_registration_time_ends,
        );
        return ();
    }

    func participate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        account: felt, amount_paid: Uint256, amount: Uint256
    ) {
        alloc_locals;
        let (the_round) = IDO_purchase_round.read();
        let (block_timestamp) = get_block_timestamp();

        // with_attr error_message("participate::invalid signature") {
        //     check_participation_signature(sig_len, sig, account, amount);
        // }
        with_attr error_message(
                "participate::Purchase round has not started yet") {
            assert_le_felt(the_round.time_starts, block_timestamp);
        }
        with_attr error_message("participate::Purchase round is over") {
            assert_le_felt(block_timestamp, the_round.time_ends);
        }
        let allocation = get_allocation(account);
        with_attr error_message("participate::No allocation") {
            assert_lt_felt(0, allocation);
        }

        _participate(account, amount_paid, amount, block_timestamp, the_round);
        return ();
    }

    func _participate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        account: felt,
        amount_paid: Uint256,
        amount: Uint256,
        block_timestamp: felt,
        the_round: PurchaseRound,
    ) {
        alloc_locals;
        let (address_this: felt) = get_contract_address();

        // Validations
        with_attr error_message("participate::Crossing max participation") {
            let (amount_check: felt) = uint256_le(amount, the_round.max_participation);
            assert amount_check = TRUE;
        }
        // with_attr error_message("participate::User not registered") {
        //     let (_is_registered) = is_registered.read(account);
        //     assert _is_registered = TRUE;
        // }
        with_attr error_message(
                "participate::Purchase round has not started yet") {
            assert_le_felt(the_round.time_starts, block_timestamp);
        }
        with_attr error_message("participate::User participated") {
            let user_participated = have_user_participated(account);
            assert user_participated = FALSE;
        }
        with_attr error_message("participate::Purchase round is over") {
            assert_le_felt(block_timestamp, the_round.time_ends);
        }

        // with_attr error_message("participate::Account address is the zero address") {
        //     assert_not_zero(account);
        // }
        // with_attr error_message("participate::Amount paid is zero") {
        //     let (amount_paid_check: felt) = uint256_lt(Uint256(0, 0), amount_paid);
        //     assert amount_paid_check = TRUE;
        // }

        let (the_sale: Sale) = get_current_sale();
        with_attr error_message("participate::The IDO token price is not set") {
            let (token_price_check: felt) = uint256_lt(Uint256(0, 0), the_sale.token_price);
            assert token_price_check = TRUE;
        }

        let (factory_address) = IDO_ido_factory_contract_address.read();
        let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(
            contract_address=factory_address
        );
        with_attr error_message("participate::Payment token address not set") {
            assert_not_zero(pmt_token_addr);
        }

        let (decimals) = IERC20.decimals(pmt_token_addr);
        let (local power) = pow(10, decimals);
        let (number_of_tokens_buying: Uint256) = SafeUint256.mul(amount_paid, Uint256(power, 0));
        let (number_of_tokens_buying_mod, _) = SafeUint256.div_rem(
            number_of_tokens_buying, the_sale.token_price
        );

        // Must buy more than 0 tokens
        with_attr error_message("participate::Can't buy 0 tokens") {
            let (is_tokens_buying_valid: felt) = uint256_lt(
                Uint256(0, 0), number_of_tokens_buying_mod
            );
            assert is_tokens_buying_valid = TRUE;
        }

        // Check user allocation
        with_attr error_message("participate::Exceeding allowance") {
            let (valid_allocation: felt) = uint256_le(number_of_tokens_buying_mod, amount);
            assert valid_allocation = TRUE;
        }

        // Require that amountOfTokensBuying is less than sale token leftover cap
        with_attr error_message("participate::Not enough tokens to sell") {
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
        IDO_sale.write(upd_sale);

        // Add participation for user.
        let new_purchase = Participation(
            amount_bought=number_of_tokens_buying_mod,
            amount_paid=amount_paid,
            time_participated=block_timestamp,
            last_portion_withdrawn=0,
        );
        set_user_participation(account, new_purchase);

        let (pmt_success: felt) = IERC20.transferFrom(
            pmt_token_addr, account, address_this, amount_paid
        );
        with_attr error_message("participate::Participation payment failed") {
            assert pmt_success = TRUE;
        }
        TokensSold.emit(user_address=account, amount=number_of_tokens_buying_mod);
        return ();
    }

    func deposit_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
        alloc_locals;
        let (address_caller: felt) = get_caller_address();
        let (address_this: felt) = get_contract_address();
        let (the_sale) = get_current_sale();
        with_attr error_message(
                "deposit_tokens::Tokens deposit can be done only once") {
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
        IDO_sale.write(upd_sale);

        let token_address = the_sale.token;
        let tokens_to_transfer = the_sale.amount_of_tokens_to_sell;
        let (transfer_success: felt) = IERC20.transferFrom(
            token_address, address_caller, address_this, tokens_to_transfer
        );
        with_attr error_message("deposit_tokens::Token transfer failed") {
            assert transfer_success = TRUE;
        }
        return ();
    }

    func withdraw_tokens{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        portion_id: felt
    ) {
        alloc_locals;
        let (address_caller: felt) = get_caller_address();
        let (address_this: felt) = get_contract_address();
        let (the_sale) = get_current_sale();
        let (block_timestamp) = get_block_timestamp();
        let (participation) = IDO_user_to_participation.read(address_caller);

        with_attr error_message("withdraw_tokens::Portion id can't be zero") {
            assert_not_zero(portion_id);
        }

        with_attr error_message(
                "withdraw_tokens::Tokens can not be withdrawn yet") {
            assert_le_felt(the_sale.tokens_unlock_time, block_timestamp);
        }

        with_attr error_message("withdraw_tokens::Invlaid portion id") {
            assert_le_felt(participation.last_portion_withdrawn, portion_id);
        }

        let participation_upd = Participation(
            amount_bought=participation.amount_bought,
            amount_paid=participation.amount_paid,
            time_participated=participation.time_participated,
            last_portion_withdrawn=portion_id,
        );
        set_user_participation(address_caller, participation_upd);

        return ();
    }

    func withdraw_from_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
        let (address_caller: felt) = get_caller_address();
        let (factory_address) = IDO_ido_factory_contract_address.read();
        let (pmt_token_addr) = IAstralyIDOFactory.get_payment_token_address(factory_address);
        let (the_sale: Sale) = get_current_sale();

        with_attr error_message(
                "withdraw_from_contract::Raised funds already withdrawn") {
            assert the_sale.raised_funds_withdrawn = FALSE;
        }

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
        IDO_sale.write(upd_sale);

        let (token_transfer_success: felt) = IERC20.transfer(
            pmt_token_addr, address_caller, the_sale.total_raised
        );
        with_attr error_message(
                "withdraw_from_contract::Token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        return ();
    }

    func withdraw_leftovers{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
        let (address_caller: felt) = get_caller_address();
        let (the_sale: Sale) = get_current_sale();

        let (block_timestamp) = get_block_timestamp();

        with_attr error_message("withdraw_leftovers::Sale not ended") {
            assert_le_felt(the_sale.sale_end, block_timestamp);
        }

        with_attr error_message(
                "withdraw_leftovers::Leftovers already withdrawn") {
            assert the_sale.leftover_withdrawn = FALSE;
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
        IDO_sale.write(upd_sale);

        let (leftover) = SafeUint256.sub_le(
            the_sale.amount_of_tokens_to_sell, the_sale.total_tokens_sold
        );
        let (token_transfer_success: felt) = IERC20.transfer(
            the_sale.token, address_caller, leftover
        );
        with_attr error_message("withdraw_leftovers::Token transfer failed") {
            assert token_transfer_success = TRUE;
        }

        return ();
    }

    func get_random_number{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        rnd: felt
    ) {
        let (ido_factory_address) = IDO_ido_factory_contract_address.read();
        let (rnd_nbr_gen_addr) = IAstralyIDOFactory.get_random_number_generator_address(
            contract_address=ido_factory_address
        );
        with_attr error_message(
                "get_random_number::Random number generator address not set in the factory") {
            assert_not_zero(rnd_nbr_gen_addr);
        }
        let (rnd_felt) = IXoroshiro.next(contract_address=rnd_nbr_gen_addr);
        with_attr error_message(
                "get_random_number::Invalid random number value") {
            assert_not_zero(rnd_felt);
        }
        return (rnd=rnd_felt);
    }

    func register_user{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr: SignatureBuiltin*,
    }(signature_len: felt, signature: felt*, signature_expiration: felt) {
        alloc_locals;
        let (the_reg) = get_registration();
        let (block_timestamp) = get_block_timestamp();
        let (caller) = get_caller_address();

        with_attr error_message("register_user::Registration window is closed") {
            assert_le_felt(the_reg.registration_time_starts, block_timestamp);
            assert_le_felt(block_timestamp, the_reg.registration_time_ends);
        }

        with_attr error_message("register_user::Invalid signature") {
            check_registration_signature(signature_len, signature, signature_expiration, caller);
        }
        with_attr error_message("register_user::Signature expired") {
            assert_lt_felt(block_timestamp, signature_expiration);
        }
        let is_user_reg: felt = is_registered(caller);
        with_attr error_message("register_user::User already registered") {
            assert is_user_reg = FALSE;
        }

        // let (score : felt) = IScorer.getScore(caller); TODO:
        let score = 99;

        _register_user(caller, the_reg, score);

        UserRegistered.emit(user_address=caller);
        return ();
    }

    func _register_user{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        caller: felt, curr_registration: Registration, score: felt
    ) {
        alloc_locals;
        let (_user_registration_index) = IDO_user_registration_index.read(caller);

        if (_user_registration_index == 0) {
            let (registrants_sum: Uint256) = SafeUint256.add(
                curr_registration.number_of_registrants, Uint256(low=1, high=0)
            );

            let upd_reg = Registration(
                curr_registration.registration_time_starts,
                curr_registration.registration_time_ends,
                registrants_sum,
            );
            IDO_registration.write(upd_reg);

            let (_users_registrations_len: felt) = IDO_users_registrations_len.read();
            IDO_users_registrations.write(
                _users_registrations_len, UserRegistrationDetails(caller, score)
            );
            IDO_users_registrations_len.write(_users_registrations_len + 1);

            IDO_user_registration_index.write(caller, _users_registrations_len);
        } else {
            let (
                current_user_registrations_details: UserRegistrationDetails
            ) = IDO_users_registrations.read(_user_registration_index);
            tempvar new_user_reg_score = current_user_registrations_details.score + score;
            IDO_users_registrations.write(
                _user_registration_index, UserRegistrationDetails(caller, new_user_reg_score)
            );
        }
        let (the_sale) = get_current_sale();
        let (curr_winners_len: felt) = IDO_winners_arr_len.read();

        let (winners_max_len: felt) = IDO.get_max_winners_len();
        let _is_lt: felt = is_lt(curr_winners_len, winners_max_len);

        tempvar caller_registration_details = UserRegistrationDetails(caller, score);

        if (_is_lt == TRUE) {
            IDO_winners_arr.write(curr_winners_len, caller_registration_details);
            IDO_winners_arr_len.write(curr_winners_len + 1);
            increase_winner_count(caller);
            return ();
        } else {
            let (rnd: felt) = get_random_number();
            let (_, rnd_index) = unsigned_div_rem(rnd, curr_winners_len);
            let (curr_user_reg_values: UserRegistrationDetails) = IDO_winners_arr.read(rnd_index);

            let (rnd2: felt) = get_random_number();
            let (_users_registrations_len: felt) = IDO_users_registrations_len.read();
            let (_, rnd_index2) = unsigned_div_rem(rnd2, _users_registrations_len);
            let (local rnd_user_reg_values: UserRegistrationDetails) = IDO_users_registrations.read(
                rnd_index2
            );

            let replace_with_caller: felt = is_le_felt(rnd_user_reg_values.score, score);

            if (replace_with_caller == TRUE) {
                let have_lower_score: felt = is_le_felt(
                    curr_user_reg_values.score, caller_registration_details.score
                );
                if (have_lower_score == TRUE) {
                    IDO_winners_arr.write(rnd_index, caller_registration_details);
                    increase_winner_count(caller_registration_details.address);
                    decrease_winner_count(curr_user_reg_values.address);
                    return ();
                }
            }

            let have_lower_score: felt = is_le_felt(
                curr_user_reg_values.score, rnd_user_reg_values.score
            );
            if (have_lower_score == TRUE) {
                IDO_winners_arr.write(rnd_index, rnd_user_reg_values);
                increase_winner_count(rnd_user_reg_values.address);
                decrease_winner_count(curr_user_reg_values.address);
                return ();
            }
        }
        return ();
    }

    func increase_winner_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) {
        let (current_winner_count: felt) = IDO_winners.read(address);
        IDO_winners.write(address, current_winner_count + 1);

        return ();
    }

    func decrease_winner_count{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) {
        let (current_winner_count: felt) = IDO_winners.read(address);
        if (current_winner_count == 0) {
            return ();
        }
        IDO_winners.write(address, current_winner_count - 1);

        return ();
    }

    func check_registration_signature{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        ecdsa_ptr: SignatureBuiltin*,
        range_check_ptr,
    }(sig_len: felt, sig: felt*, sig_expiration_timestamp: felt, caller: felt) {
        alloc_locals;
        let (admin) = IDO_admin_address.read();
        let (this) = get_contract_address();

        let (user_hash) = hash2{hash_ptr=pedersen_ptr}(sig_expiration_timestamp, caller);
        let (final_hash) = hash2{hash_ptr=pedersen_ptr}(user_hash, this);

        // Verify the user's signature.
        let (is_valid) = IAccount.isValidSignature(admin, final_hash, sig_len, sig);
        assert is_valid = TRUE;
        return ();
    }

    func check_participation_signature{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr: SignatureBuiltin*,
    }(sig_len: felt, sig: felt*, caller: felt, amount: Uint256) {
        alloc_locals;
        let (admin) = IDO_admin_address.read();
        let (this) = get_contract_address();

        let (hash1) = hash2{hash_ptr=pedersen_ptr}(caller, amount.low);
        let (hash2_) = hash2{hash_ptr=pedersen_ptr}(hash1, amount.high);
        let (hash3) = hash2{hash_ptr=pedersen_ptr}(hash2_, this);

        // Verify the user's signature.
        let (is_valid) = IAccount.isValidSignature(admin, hash3, sig_len, sig);
        assert is_valid = TRUE;
        return ();
    }
}
