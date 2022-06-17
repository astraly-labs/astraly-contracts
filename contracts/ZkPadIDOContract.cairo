%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import (
    assert_nn_le,
    assert_not_equal,
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
)
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc

from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_lt,
    uint256_checked_sub_le,
    uint256_checked_mul,
    uint256_checked_div_rem,
)

from InterfaceAll import IZKPadIDOFactory, IXoroshiro, XOROSHIRO_ADDR
from contracts.utils.ZkPadConstants import DAYS_30
from contracts.utils.ZkPadUtils import get_is_equal, uint256_max
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_eq,
    uint256_le,
    uint256_lt,
    uint256_check,
)
from contracts.utils.Uint256_felt_conv import _felt_to_uint, _uint_to_felt
from contracts.utils import uint256_is_zero
from contracts.utils.Math64x61 import (
    Math64x61_fromUint256,
    Math64x61_toUint256,
    Math64x61_div,
    Math64x61_fromFelt,
    Math64x61_toFelt,
    Math64x61_mul,
    Math64x61_add,
)

const Math64x61_BOUND_LOCAL = 2 ** 64

struct Sale:
    # Token being sold (interface)
    member token : felt
    # Is sale created (boolean)
    member is_created : felt
    # Are earnings withdrawn (boolean)
    member raised_funds_withdrawn : felt
    # Is leftover withdrawn (boolean)
    member leftover_withdrawn : felt
    # Have tokens been deposited (boolean)
    member tokens_deposited : felt
    # Address of sale owner
    member sale_owner : felt
    # Price of the token quoted - needed as its the price set for the IDO
    member token_price : Uint256
    # Amount of tokens to sell
    member amount_of_tokens_to_sell : Uint256
    # Total tokens being sold
    member total_tokens_sold : Uint256
    # Total winning lottery tickets
    member total_winning_tickets : Uint256
    # Total Raised (what are using to track this?)
    member total_raised : Uint256
    # Sale end time
    member sale_end : felt
    # When tokens can be withdrawn
    member tokens_unlock_time : felt
    # Cap on the number of lottery tickets to burn when registring
    member lottery_tickets_burn_cap : Uint256
    # Number of users participated in the sale
    member number_of_participants : Uint256
end

struct Participation:
    member amount_bought : Uint256
    member amount_paid : Uint256
    member time_participated : felt
    # member round_id : felt
    member last_portion_withdrawn : felt
end

struct Registration:
    member registration_time_starts : felt
    member registration_time_ends : felt
    member number_of_registrants : Uint256
end

struct Purchase_Round:
    member time_starts : felt
    member time_ends : felt
    member number_of_purchases : Uint256
end

struct Distribution_Round:
    member time_starts : felt
end

# Sale
@storage_var
func sale() -> (res : Sale):
end

# Registration
@storage_var
func registration() -> (res : Registration):
end

@storage_var
func purchase_round() -> (res : Purchase_Round):
end

@storage_var
func disctribution_round() -> (res : Distribution_Round):
end

# Mapping user to his participation
@storage_var
func user_to_participation(user_address : felt) -> (res : Participation):
end

# Mapping user to number of winning lottery tickets
@storage_var
func user_to_winning_lottery_tickets(user_address : felt) -> (res : Uint256):
end

# Mapping user to number of allocations
@storage_var
func address_to_allocations(user_address : felt) -> (res : Uint256):
end

# total allocations given
@storage_var
func total_allocations_given() -> (res : Uint256):
end

# mapping user to is registered or not
@storage_var
func is_registered(user_address : felt) -> (res : felt):
end

# mapping user to is participated or not
@storage_var
func has_participated(user_address : felt) -> (res : felt):
end

# Times when portions are getting unlocked
@storage_var
func vesting_portions_unlock_time_array(i : felt) -> (res : felt):
end

# Percent of the participation user can withdraw
@storage_var
func vesting_percent_per_portion_array(i : felt) -> (res : Uint256):
end

@storage_var
func number_of_vesting_portions() -> (res : felt):
end

# Precision for percent for portion vesting
@storage_var
func portion_vesting_precision() -> (res : Uint256):
end

# Max vesting time shift
@storage_var
func max_vesting_time_shift() -> (res : felt):
end

@storage_var
func ido_factory_contract_address() -> (res : felt):
end

@storage_var
func ido_allocation() -> (res : Uint256):
end

func only_sale_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (the_sale) = sale.read()
    with_attr error_message("ZkPadIDOContract: only sale owner can call this function"):
        assert the_sale.sale_owner = caller
    end

    return ()
end

@event
func tokens_sold(user_address : felt, amount : Uint256):
end

@event
func user_registered(
    user_address : felt, winning_lottery_tickets : Uint256, amount_burnt : Uint256
):
end

@event
func token_price_set(new_price : Uint256):
end

@event
func allocation_computed(allocation : Uint256, sold : Uint256):
end

@event
func tokens_withdrawn(user_address : felt, amount : Uint256):
end

@event
func sale_created(
    sale_owner_address : felt,
    token_price : Uint256,
    amount_of_tokens_to_sell : Uint256,
    sale_end : felt,
    tokens_unlock_time : felt,
):
end

@event
func registration_time_set(registration_time_starts : felt, registration_time_ends : felt):
end

@event
func purchase_round_time_set(purchase_time_starts : felt, purchase_time_ends : felt):
end

@event
func distribtion_round_time_set(dist_time_starts : felt):
end

@event
func IDO_Created(new_ido_contract_address : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _admin_address : felt
):
    assert_not_zero(_admin_address)
    Ownable_initializer(_admin_address)

    let (caller : felt) = get_caller_address()

    let (address_this : felt) = get_contract_address()
    IDO_Created.emit(address_this)
    return ()
end

#############################################
# #                 GETTERS                 ##
#############################################

@view
func get_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (the_reg) = registration.read()
    return (res=the_reg.registration_time_starts)
end

@view
func get_current_sale{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Sale
):
    let (the_sale) = sale.read()
    return (res=the_sale)
end

@view
func get_user_info{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (
    participation : Participation,
    tickets : Uint256,
    allocations : Uint256,
    is_registered : felt,
    has_participated : felt,
):
    let (_participation) = user_to_participation.read(account)
    let (_winning_tickets) = user_to_winning_lottery_tickets.read(account)
    let (_allocations) = address_to_allocations.read(account)
    let (_is_registered) = is_registered.read(account)
    let (_has_participated) = has_participated.read(account)
    return (
        participation=_participation,
        tickets=_winning_tickets,
        allocations=_allocations,
        is_registered=_is_registered,
        has_participated=_has_participated,
    )
end

@view
func get_purchase_round{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Purchase_Round
):
    let (round) = purchase_round.read()
    return (res=round)
end

@view
func get_registration{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Registration
):
    let (_registration) = registration.read()
    return (res=_registration)
end

@view
func get_distribution_round{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    ) -> (res : Distribution_Round):
    let (round) = disctribution_round.read()
    return (res=round)
end

@view
func get_vesting_portion_percent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    portion_id : felt
) -> (res : Uint256):
    let (percent) = vesting_percent_per_portion_array.read(portion_id)
    return (res=percent)
end

@view
func get_vestion_portion_unlock_time{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(portion_id : felt) -> (res : felt):
    let (unlock_time) = vesting_portions_unlock_time_array.read(portion_id)
    return (res=unlock_time)
end

@view
func get_number_of_vesting_portions{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}() -> (res : felt):
    let (nbr_of_portions) = number_of_vesting_portions.read()
    return (res=nbr_of_portions)
end

#############################################
# #                 EXTERNALS               ##
#############################################

@external
func set_vesting_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times : felt*,
    _percents_len : felt,
    _percents : Uint256*,
    _max_vesting_time_shift : felt,
):
    alloc_locals
    Ownable_only_owner()

    with_attr error_message("ZkPadIDOContract::set_vesting_params unlocking times array length 0"):
        assert_not_zero(_unlocking_times_len)
    end
    with_attr error_message("ZkPadIDOContract::set_vesting_params percents array length 0"):
        assert_not_zero(_percents_len)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_vesting_params unlocking times and percents arrays different lengths"):
        assert _unlocking_times_len = _percents_len
    end

    let (local _portion_vesting_precision : Uint256) = portion_vesting_precision.read()
    with_attr error_message(
            "ZkPadIDOContract::set_vesting_params portion vesting precision is zero"):
        let (percision_check : felt) = uint256_lt(Uint256(0, 0), _portion_vesting_precision)
        assert percision_check = TRUE
    end

    with_attr error_message(
            "ZkPadIDOContract::set_vesting_params max vesting time shift more than 30 days"):
        assert_le(_max_vesting_time_shift, DAYS_30)
    end

    max_vesting_time_shift.write(_max_vesting_time_shift)
    number_of_vesting_portions.write(_percents_len)

    let percent_sum = Uint256(0, 0)
    # # local array_index = 0
    let array_index = 1

    populate_vesting_params_rec(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, array_index
    )

    let (percent_sum) = array_sum(_percents, _percents_len)
    let (percent_sum_check) = uint256_eq(percent_sum, _portion_vesting_precision)

    with_attr error_message(
            "ZkPadIDOContract::set_vesting_params Vesting percentages do not add up"):
        assert percent_sum_check = TRUE
    end

    return ()
end

func populate_vesting_params_rec{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times : felt*,
    _percents_len : felt,
    _percents : Uint256*,
    _array_index : felt,
):
    alloc_locals
    assert _unlocking_times_len = _percents_len

    if _unlocking_times_len == 0:
        return ()
    end

    let percent0 = _percents[0]
    vesting_portions_unlock_time_array.write(_array_index, _unlocking_times[0])
    # vesting_percent_per_portion_array.write(_array_index, _percents[0])
    vesting_percent_per_portion_array.write(_array_index, percent0)
    return populate_vesting_params_rec(
        _unlocking_times_len=_unlocking_times_len - 1,
        _unlocking_times=_unlocking_times + 1,
        _percents_len=_percents_len - 1,
        _percents=_percents + Uint256.SIZE,
        _array_index=_array_index + 1,
    )
end

func array_sum{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    arr : Uint256*, size : felt
) -> (sum : Uint256):
    if size == 0:
        # parenthesis required for return statement
        return (sum=Uint256(0, 0))
    end

    # recursive call to array_sum, arr = arr[0],
    let (sum_of_rest) = array_sum(arr=arr + Uint256.SIZE, size=size - 1)
    # [...] dereferences to value of memory address which is first element of arr
    # recurisvely calls array_sum with arr+1 which is next element in arr
    # recursion stops when size == 0
    # return (sum=[arr] + sum_of_rest)
    let (the_sum) = uint256_checked_add([arr], sum_of_rest)
    return (sum=the_sum)
end

@external
func set_sale_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _token_address : felt,
    _sale_owner_address : felt,
    _token_price : Uint256,
    _amount_of_tokens_to_sell : Uint256,
    _sale_end_time : felt,
    _tokens_unlock_time : felt,
    _portion_vesting_precision : Uint256,
    _lottery_tickets_burn_cap : Uint256,
):
    alloc_locals
    Ownable_only_owner()
    let (the_sale) = sale.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadIDOContract::set_sale_params Sale is already created"):
        assert the_sale.is_created = FALSE
    end
    with_attr error_message("ZkPadIDOContract::set_sale_params Sale owner address can not be 0"):
        assert_not_zero(_sale_owner_address)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_sale_params IDO Token price must be greater than zero"):
        let (token_price_check : felt) = uint256_lt(Uint256(0, 0), _token_price)
        assert token_price_check = TRUE
    end
    with_attr error_message(
            "ZkPadIDOContract::set_sale_params Number of IDO Tokens to sell must be greater than zero"):
        let (token_to_sell_check : felt) = uint256_lt(Uint256(0, 0), _amount_of_tokens_to_sell)
        assert token_to_sell_check = TRUE
    end
    with_attr error_message("ZkPadIDOContract::set_sale_params Bad input"):
        assert_lt(block_timestamp, _sale_end_time)
        assert_lt(block_timestamp, _tokens_unlock_time)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_sale_params portion vesting percision should be at least 100"):
        let (vesting_precision_check : felt) = uint256_le(
            Uint256(100, 0), _portion_vesting_precision
        )
        assert vesting_precision_check = TRUE
    end

    # set params
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
        total_winning_tickets=Uint256(0, 0),
        total_raised=Uint256(0, 0),
        sale_end=_sale_end_time,
        tokens_unlock_time=_tokens_unlock_time,
        lottery_tickets_burn_cap=_lottery_tickets_burn_cap,
        number_of_participants=Uint256(0, 0),
    )
    sale.write(new_sale)
    # Set portion vesting precision
    portion_vesting_precision.write(_portion_vesting_precision)
    # emit event
    sale_created.emit(
        sale_owner_address=_sale_owner_address,
        token_price=_token_price,
        amount_of_tokens_to_sell=_amount_of_tokens_to_sell,
        sale_end=_sale_end_time,
        tokens_unlock_time=_tokens_unlock_time,
    )
    return ()
end

@external
func set_sale_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _sale_token_address : felt
):
    Ownable_only_owner()
    let (the_sale) = sale.read()
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
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=the_sale.number_of_participants,
    )
    sale.write(upd_sale)
    return ()
end

@external
func set_registration_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _registration_time_starts : felt, _registration_time_ends : felt
):
    Ownable_only_owner()
    let (the_sale) = sale.read()
    let (the_reg) = registration.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadIDOContract::set_registration_time Sale not created yet"):
        assert the_sale.is_created = TRUE
    end
    # with_attr error_message(
    #         "ZkPadIDOContract::set_registration_time the registration start time is already set"):
    #     assert the_reg.registration_time_starts = 0
    # end
    with_attr error_message(
            "ZkPadIDOContract::set_registration_time registration start/end times issue"):
        assert_le(block_timestamp, _registration_time_starts)
        assert_lt(_registration_time_starts, _registration_time_ends)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_registration_time registration end has to be before sale end"):
        assert_lt(_registration_time_ends, the_sale.sale_end)
    end
    let upd_reg = Registration(
        registration_time_starts=_registration_time_starts,
        registration_time_ends=_registration_time_ends,
        number_of_registrants=the_reg.number_of_registrants,
    )
    registration.write(upd_reg)
    registration_time_set.emit(
        registration_time_starts=_registration_time_starts,
        registration_time_ends=_registration_time_ends,
    )
    return ()
end

@external
func set_purchase_round_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _purchase_time_starts : felt, _purchase_time_ends : felt
):
    Ownable_only_owner()
    let (the_reg) = registration.read()
    let (the_purchase) = purchase_round.read()
    with_attr error_message("ZkPadIDOContract::set_purchase_round_params Bad input"):
        assert_not_zero(_purchase_time_starts)
        assert_not_zero(_purchase_time_ends)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_purchase_round_params end time must be after start end"):
        assert_lt(_purchase_time_starts, _purchase_time_ends)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_purchase_round_params registration time not set yet"):
        assert_not_zero(the_reg.registration_time_starts)
        assert_not_zero(the_reg.registration_time_ends)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_purchase_round_params start time must be after registration end"):
        assert_lt(the_reg.registration_time_ends, _purchase_time_starts)
    end
    let upd_purchase = Purchase_Round(
        time_starts=_purchase_time_starts,
        time_ends=_purchase_time_ends,
        number_of_purchases=the_purchase.number_of_purchases,
    )
    purchase_round.write(upd_purchase)
    purchase_round_time_set.emit(
        purchase_time_starts=_purchase_time_starts, purchase_time_ends=_purchase_time_ends
    )
    return ()
end

@external
func set_dist_round_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _dist_time_starts : felt
):
    Ownable_only_owner()
    let (the_purchase) = purchase_round.read()
    let (the_dist) = disctribution_round.read()
    with_attr error_message("ZkPadIDOContract::set_dist_round_params Bad input"):
        assert_not_zero(_dist_time_starts)
    end
    with_attr error_message("ZkPadIDOContract::set_dist_round_params Purchase round not set yet"):
        assert_not_zero(the_purchase.time_starts)
        assert_not_zero(the_purchase.time_ends)
    end
    with_attr error_message(
            "ZkPadIDOContract::set_dist_round_params Disctribtion must start after purchase round ends"):
        assert_lt(the_purchase.time_ends, _dist_time_starts)
    end
    let upd_dist = Distribution_Round(time_starts=_dist_time_starts)
    disctribution_round.write(upd_dist)
    distribtion_round_time_set.emit(dist_time_starts=_dist_time_starts)
    return ()
end

@external
func register_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256, account : felt, nb_quest : felt
) -> (res : felt):
    alloc_locals
    let (the_reg) = registration.read()
    let (block_timestamp) = get_block_timestamp()
    let (the_sale) = sale.read()

    let (factory_address) = ido_factory_contract_address.read()
    let (lottery_ticket_address) = IZKPadIDOFactory.get_lottery_ticket_contract_address(
        contract_address=factory_address
    )
    with_attr error_message(
            "ZkPadIDOContract::register_user Lottery ticket contract address not set"):
        assert_not_zero(lottery_ticket_address)
    end
    let (caller) = get_caller_address()
    with_attr error_message(
            "ZkPadIDOContract::register_user only the lottery ticket contract can make this call"):
        assert caller = lottery_ticket_address
    end

    with_attr error_message("ZkPadIDOContract::register_user account address is the zero address"):
        assert_not_zero(account)
    end
    with_attr error_message(
            "ZkPadIDOContract::register_user allocation claim amount not greater than 0"):
        let (amount_check : felt) = uint256_lt(Uint256(0, 0), amount)
        assert amount_check = TRUE
    end
    with_attr error_message("ZkPadIDOContract::register_user Registration window is closed"):
        assert_le(the_reg.registration_time_starts, block_timestamp)
        assert_le(block_timestamp, the_reg.registration_time_ends)
    end

    let (is_user_reg) = is_registered.read(account)
    if is_user_reg == 0:
        is_registered.write(account, TRUE)
        let (local registrants_sum : Uint256) = uint256_checked_add(
            the_reg.number_of_registrants, Uint256(low=1, high=0)
        )

        let upd_reg = Registration(
            registration_time_starts=the_reg.registration_time_starts,
            registration_time_ends=the_reg.registration_time_ends,
            number_of_registrants=registrants_sum,
        )
        registration.write(upd_reg)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    let (adjusted_amount : Uint256) = get_adjusted_amount(
        _amount=amount, _cap=the_sale.lottery_tickets_burn_cap
    )
    let (current_winning : Uint256) = user_to_winning_lottery_tickets.read(account)
    let (new_winning : Uint256) = draw_winning_tickets(
        tickets_burnt=adjusted_amount, nb_quest=nb_quest
    )
    let (local winning_tickets_sum : Uint256) = uint256_checked_add(current_winning, new_winning)

    user_to_winning_lottery_tickets.write(account, winning_tickets_sum)

    let (local total_winning_tickets_sum : Uint256) = uint256_checked_add(
        the_sale.total_winning_tickets, new_winning
    )

    let upd_sale = Sale(
        token=the_sale.token,
        is_created=the_sale.is_created,
        raised_funds_withdrawn=the_sale.raised_funds_withdrawn,
        leftover_withdrawn=the_sale.leftover_withdrawn,
        tokens_deposited=the_sale.tokens_deposited,
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
    )
    sale.write(upd_sale)

    user_registered.emit(
        user_address=account, winning_lottery_tickets=new_winning, amount_burnt=adjusted_amount
    )
    return (res=TRUE)
end

func get_adjusted_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _amount : Uint256, _cap : Uint256
) -> (res : Uint256):
    let (is_amount_le_cap : felt) = uint256_le(_amount, _cap)
    if is_amount_le_cap == TRUE:
        return (res=_amount)
    else:
        return (res=_cap)
    end
end

# This function will calculate allocation (USD/IDO Token) and will be triggered using the keeper network
# does this method need anu inputs? or will it only use the number of users and winning tickets?
@external
func calculate_allocation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    Ownable_only_owner()
    let (current_allocation : Uint256) = ido_allocation.read()
    with_attr error_message("ZkPadIDOContract::calculate_allocation allocation already calculated"):
        let (allocation_check : felt) = uint256_eq(current_allocation, Uint256(0, 0))
        assert allocation_check = TRUE
    end
    let (the_sale : Sale) = sale.read()
    local to_sell : Uint256 = the_sale.amount_of_tokens_to_sell
    local total_winning_tickets : Uint256 = the_sale.total_winning_tickets

    # Compute the allocation : amount_of_tokens_to_sell / total_winning_tickets
    let (the_allocation : Uint256, _) = uint256_checked_div_rem(to_sell, total_winning_tickets)
    # with_attr error_message("ZkPadIDOContract::calculate_allocation calculation error"):
    #     assert the_allocation * the_sale.total_winning_tickets = the_sale.amount_of_tokens_to_sell
    # end
    ido_allocation.write(the_allocation)
    allocation_computed.emit(allocation=the_allocation, sold=the_sale.amount_of_tokens_to_sell)
    return ()
end

# this function will call the VRF and determine the number of winning tickets (if any)
@view
func draw_winning_tickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tickets_burnt : Uint256, nb_quest : felt
) -> (res : Uint256):
    alloc_locals
    let (single_t : felt) = uint256_le(tickets_burnt, Uint256(1, 0))
    if single_t == TRUE:
        # One ticket
        let (rnd) = get_random_number()
        # let (f_rnd) = _uint_to_felt(rnd)
        let (q, r) = unsigned_div_rem(rnd, 9)
        let (is_won : felt) = is_le(r, 2)
        if is_won == TRUE:
            let (res : Uint256) = _felt_to_uint(1)
            return (res)
        end
        let (res : Uint256) = _felt_to_uint(0)
        return (res)
    end

    let (rnd) = get_random_number()
    # let (max_uint : Uint256) = uint256_max()

    # Tickets_burnt * 0.6
    let (a) = Math64x61_fromFelt(3)
    let (b) = Math64x61_fromFelt(5)
    let (div) = Math64x61_div(a, b)
    let (fixed_tickets_felt) = _uint_to_felt(tickets_burnt)
    let (num1) = Math64x61_mul(fixed_tickets_felt, div)
    # Nb_quest * 5
    let (num2) = Math64x61_mul(nb_quest, 5)

    # Add them
    let (sum) = Math64x61_add(num1, num2)

    # Compute rand/max
    let (fixed_rand) = Math64x61_fromFelt(rnd)
    let (rand_factor) = Math64x61_div(rnd, Math64x61_BOUND_LOCAL - 1)

    # Finally multiply both results
    let (fixed_winning) = Math64x61_mul(rand_factor, sum)

    let (winning : Uint256) = Math64x61_toUint256(fixed_winning)

    return (res=winning)
end

func get_random_number{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    rnd : felt
):
    let (ido_factory_address) = ido_factory_contract_address.read()
    let (rnd_nbr_gen_addr) = IZKPadIDOFactory.get_random_number_generator_address(
        contract_address=ido_factory_address
    )
    with_attr error_message(
            "ZkPadIDOContract::get_random_number random number generator address not set in the factory"):
        assert_not_zero(rnd_nbr_gen_addr)
    end
    let (rnd_felt) = IXoroshiro.next(contract_address=rnd_nbr_gen_addr)
    with_attr error_message("ZkPadIDOContract::get_random_number invalid random number value"):
        assert_not_zero(rnd_felt)
    end
    return (rnd=rnd_felt)
end

@external
func participate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount_paid : Uint256
) -> (res : felt):
    alloc_locals
    let (account : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (the_sale) = sale.read()
    let (block_timestamp) = get_block_timestamp()
    let (the_round) = purchase_round.read()

    # Validations
    with_attr error_message("ZkPadIDOContract::participate Purchase round has not started yet"):
        assert_le(the_round.time_starts, block_timestamp)
    end
    with_attr error_message("ZkPadIDOContract::participate Purchase round is over"):
        assert_le(block_timestamp, the_round.time_ends)
    end
    let (user_participated) = has_participated.read(account)
    with_attr error_message("ZkPadIDOContract::participate user participated"):
        assert user_participated = FALSE
    end
    with_attr error_message("ZkPadIDOContract::participate Account address is the zero address"):
        assert_not_zero(account)
    end
    with_attr error_message("ZkPadIDOContract::participate Amount paid is zero"):
        let (amount_paid_check : felt) = uint256_lt(Uint256(0, 0), amount_paid)
        assert amount_paid_check = TRUE
    end
    let (the_sale) = sale.read()
    with_attr error_message("ZkPadIDOContract::participate the IDO token price is not set"):
        let (token_price_check : felt) = uint256_lt(Uint256(0, 0), the_sale.token_price)
        assert token_price_check = TRUE
    end
    let (the_alloc : Uint256) = ido_allocation.read()
    with_attr error_message(
            "ZkPadIDOContract::participate The IDO token allocation has not been calculated"):
        let (allocation_check : felt) = uint256_lt(Uint256(0, 0), the_alloc)
        assert allocation_check = TRUE
    end
    let (winning_tickets : Uint256) = user_to_winning_lottery_tickets.read(account)
    with_attr error_message(
            "ZkPadIDOContract::participate account does not have any winning lottery tickets"):
        let (winning_tkts_check : felt) = uint256_lt(Uint256(0, 0), winning_tickets)
        assert winning_tkts_check = TRUE
    end
    let (max_tokens_to_purchase : Uint256) = uint256_checked_mul(winning_tickets, the_alloc)
    let (number_of_tokens_byuing, _) = uint256_checked_div_rem(amount_paid, the_sale.token_price)
    with_attr error_message("ZkPadIDOContract::participate Can't buy more than maximum allocation"):
        let (is_tokens_buying_le_max) = uint256_le(number_of_tokens_byuing, max_tokens_to_purchase)
        assert is_tokens_buying_le_max = TRUE
    end

    # Updates
    let (local total_tokens_sum : Uint256) = uint256_checked_add(
        the_sale.total_tokens_sold, number_of_tokens_byuing
    )

    let (local total_raised_sum : Uint256) = uint256_checked_add(the_sale.total_raised, amount_paid)
    let (local number_of_participants_sum : Uint256) = uint256_checked_add(
        the_sale.number_of_participants, Uint256(1, 0)
    )

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
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=total_raised_sum,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=number_of_participants_sum,
    )
    sale.write(upd_sale)

    let new_purchase = Participation(
        amount_bought=number_of_tokens_byuing,
        amount_paid=amount_paid,
        time_participated=block_timestamp,
        last_portion_withdrawn=0,
    )
    user_to_participation.write(account, new_purchase)

    has_participated.write(account, TRUE)

    let (factory_address) = ido_factory_contract_address.read()
    let (pmt_token_addr) = IZKPadIDOFactory.get_payment_token_address(
        contract_address=factory_address
    )
    with_attr error_message("ZkPadIDOContract::participate Payment token address not set"):
        assert_not_zero(pmt_token_addr)
    end
    let (pmt_success : felt) = IERC20.transferFrom(
        pmt_token_addr, account, address_this, amount_paid
    )
    with_attr error_message("ZkPadIDOContract::participate Participation payment failed"):
        assert pmt_success = TRUE
    end

    tokens_sold.emit(user_address=account, amount=number_of_tokens_byuing)
    return (res=TRUE)
end

@external
func deposit_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    only_sale_owner()
    let (address_caller : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (the_sale) = sale.read()
    with_attr error_message(
            "ZkPadIDOContract::deposit_tokens Tokens deposit can be done only once"):
        assert the_sale.tokens_deposited = FALSE
    end
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
        total_winning_tickets=the_sale.total_winning_tickets,
        total_raised=the_sale.total_raised,
        sale_end=the_sale.sale_end,
        tokens_unlock_time=the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap=the_sale.lottery_tickets_burn_cap,
        number_of_participants=the_sale.number_of_participants,
    )
    sale.write(upd_sale)

    let token_address = the_sale.token
    let tokens_to_transfer = the_sale.amount_of_tokens_to_sell
    let (transfer_success : felt) = IERC20.transferFrom(
        token_address, address_caller, address_this, tokens_to_transfer
    )
    with_attr error_message("ZkPadIDOContract::deposit_tokens token transfer failed"):
        assert transfer_success = TRUE
    end
    return ()
end

@external
func withdraw_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    portion_id : felt
):
    alloc_locals
    let (address_caller : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (the_sale) = sale.read()
    let (block_timestamp) = get_block_timestamp()
    let (participation) = user_to_participation.read(address_caller)

    with_attr error_message("ZkPadIDOContract::withdraw_tokens portion id can't be zero"):
        assert_not_zero(portion_id)
    end

    with_attr error_message("ZkPadIDOContract::withdraw_tokens Tokens can not be withdrawn yet"):
        assert_le(the_sale.tokens_unlock_time, block_timestamp)
    end

    with_attr error_message("ZkPadIDOContract::withdraw_tokens Invlaid portion id"):
        assert_le(participation.last_portion_withdrawn, portion_id)
    end

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(portion_id)

    with_attr error_message(
            "ZkPadIDOContract::withdraw_tokens invalid portion vesting unlock time"):
        assert_not_zero(vesting_portions_unlock_time)
    end

    with_attr error_message("ZkPadIDOContract::withdraw_tokens Portion has not been unlocked yet"):
        assert_le(vesting_portions_unlock_time, block_timestamp)
    end

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(portion_id)

    with_attr error_message("ZkPadIDOContract::withdraw_tokens invlaid vestion portion percent"):
        uint256_lt(Uint256(0, 0), vesting_portion_percent)
    end

    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        last_portion_withdrawn=portion_id,
    )
    user_to_participation.write(address_caller, participation_upd)

    let (amt_withdrawing_num : Uint256) = uint256_checked_mul(
        participation.amount_bought, vesting_portion_percent
    )
    let (portion_vesting_prsn : Uint256) = portion_vesting_precision.read()
    let (amt_withdrawing, _) = uint256_checked_div_rem(amt_withdrawing_num, portion_vesting_prsn)

    let (amt_withdrawing_check : felt) = uint256_lt(Uint256(0, 0), amt_withdrawing)
    if amt_withdrawing_check == TRUE:
        let token_address = the_sale.token
        let (token_transfer_success : felt) = IERC20.transfer(
            token_address, address_caller, amt_withdrawing
        )
        with_attr error_message("ZkPadIDOContract::withdraw_tokens token transfer failed"):
            assert token_transfer_success = TRUE
        end

        tokens_withdrawn.emit(user_address=address_caller, amount=amt_withdrawing)

        return ()
    else:
        return ()
    end
end

@external
func withdraw_multiple_portions{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    portion_ids_len : felt, portion_ids : felt*
):
    alloc_locals
    let (address_caller : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (the_sale) = sale.read()
    let (block_timestamp) = get_block_timestamp()
    let (participation) = user_to_participation.read(address_caller)

    let (amt_withdrawn_sum : Uint256) = withdraw_multiple_portions_rec(
        portion_ids_len, portion_ids, block_timestamp, address_caller
    )
    let (amt_withdrawing_check : felt) = uint256_lt(Uint256(0, 0), amt_withdrawn_sum)
    if amt_withdrawing_check == TRUE:
        let token_address = the_sale.token
        let (token_transfer_success : felt) = IERC20.transfer(
            token_address, address_caller, amt_withdrawn_sum
        )
        with_attr error_message(
                "ZkPadIDOContract::withdraw_multiple_portions token transfer failed"):
            assert token_transfer_success = TRUE
        end

        tokens_withdrawn.emit(user_address=address_caller, amount=amt_withdrawn_sum)
        return ()
    else:
        return ()
    end
end

func withdraw_multiple_portions_rec{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(
    _portion_ids_len : felt, _portion_ids : felt*, _block_timestamp : felt, _address_caller : felt
) -> (amt_sum : Uint256):
    alloc_locals

    if _portion_ids_len == 0:
        return (amt_sum=Uint256(0, 0))
    end

    let current_portion = _portion_ids[0]
    let (participation) = user_to_participation.read(_address_caller)
    with_attr error_message("ZkPadIDOContract::withdraw_multiple_portions_rec Invalid portion Id"):
        assert_lt(participation.last_portion_withdrawn, current_portion)
    end
    let participation_upd = Participation(
        amount_bought=participation.amount_bought,
        amount_paid=participation.amount_paid,
        time_participated=participation.time_participated,
        last_portion_withdrawn=current_portion,
    )
    user_to_participation.write(_address_caller, participation_upd)

    let (sum_of_portions) = withdraw_multiple_portions_rec(
        _portion_ids_len=_portion_ids_len - 1,
        _portion_ids=_portion_ids + 1,
        _block_timestamp=_block_timestamp,
        _address_caller=_address_caller,
    )

    let (vesting_portions_unlock_time) = vesting_portions_unlock_time_array.read(current_portion)
    with_attr error_message(
            "ZkPadIDOContract::withdraw_multiple_portions_rec invalid portion vesting unlock time"):
        assert_not_zero(vesting_portions_unlock_time)
    end
    with_attr error_message(
            "ZkPadIDOContract::withdraw_multiple_portions_rec Portion has not been unlocked yet"):
        assert_le(vesting_portions_unlock_time, _block_timestamp)
    end

    let (vesting_portion_percent) = vesting_percent_per_portion_array.read(current_portion)
    with_attr error_message(
            "ZkPadIDOContract::withdraw_multiple_portions_rec invlaid vestion portion percent"):
        uint256_lt(Uint256(0, 0), vesting_portion_percent)
    end

    let (amt_withdrawing_num : Uint256) = uint256_checked_mul(
        participation.amount_bought, vesting_portion_percent
    )
    let (portion_vesting_prsn : Uint256) = portion_vesting_precision.read()
    let (amt_withdrawing, _) = uint256_checked_div_rem(amt_withdrawing_num, portion_vesting_prsn)

    let (the_sum) = uint256_checked_add(amt_withdrawing, sum_of_portions)
    return (amt_sum=the_sum)
end
