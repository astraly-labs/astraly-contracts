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

from InterfaceAll import IAdmin, IZKPadIDOFactory, IXoroshiro, XOROSHIRO_ADDR
from contracts.utils.ZkPadConstants import DAYS_30
from contracts.utils.ZkPadUtils import get_is_equal
from starkware.starknet.common.syscalls import get_block_timestamp
from openzeppelin.utils.constants import FALSE, TRUE
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_eq,
    uint256_le,
    uint256_lt,
    uint256_check,
)
from contracts.utils.Uint256_felt_conv import _felt_to_uint, _uint_to_felt
from contracts.utils import uint256_is_zero
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_lt,
    uint256_checked_sub_le,
    uint256_checked_mul,
    uint256_checked_div_rem,
)

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
end

struct Participation:
    member amount_bought : Uint256
    member amount_paid : Uint256
    member time_participated : felt
    # member round_id : felt
    member is_portion_withdrawn_array : felt  # can't have arrays as members of the struct. Will use a felt with a bit mask
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

# Number of users participated in the sale.
@storage_var
func number_of_participants() -> (res : Uint256):
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

# Precision for percent for portion vesting
@storage_var
func portion_vesting_precision() -> (res : Uint256):
end

# Max vesting time shift
@storage_var
func max_vesting_time_shift() -> (res : felt):
end

@storage_var
func admin_contract_address() -> (res : felt):
end

@storage_var
func staking_vault_contract_address() -> (res : felt):
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

func only_admin{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (the_admin_address) = admin_contract_address.read()
    let (is_admin) = IAdmin.is_admin(contract_address=the_admin_address, user_address=caller)
    with_attr error_message("ZkPadIDOContract: only sale admin can call this function"):
        assert is_admin = 1
    end

    return ()
end

@event
func tokens_sold(user_address : felt, amount : Uint256):
end

@event
func user_registered(user_address : felt, winning_lottery_tickets : Uint256):
end

@event
func token_price_set(new_price : Uint256):
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

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _admin_address : felt, _staking_vault_address : felt, _ido_factory_contract_address : felt
):
    assert_not_zero(_admin_address)
    assert_not_zero(_staking_vault_address)
    assert_not_zero(_ido_factory_contract_address)

    let (caller) = get_caller_address()
    # for now we will pass the address of the factory until we are able to instantiate the IDO contract from the factory
    # ido_factory_contract_address.write(caller)
    ido_factory_contract_address.write(_ido_factory_contract_address)
    admin_contract_address.write(_admin_address)
    staking_vault_contract_address.write(_staking_vault_address)

    return ()
end

@external
func set_vesting_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times : felt*,
    _percents_len : felt,
    _percents : Uint256*,
    _max_vesting_time_shift : felt,
):
    alloc_locals
    only_admin()

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

    let (_portion_vesting_precision) = portion_vesting_precision.read()
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

    local percent_sum : Uint256 = Uint256(0, 0)
    local array_index = 0

    populate_vesting_params_rec(
        _unlocking_times_len, _unlocking_times, _percents_len, _percents, percent_sum, array_index
    )

    with_attr error_message("ZkPadIDOContract::set_vesting_params Percent distribution issue"):
        assert percent_sum = _portion_vesting_precision
    end

    return ()
end

func populate_vesting_params_rec{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times : felt*,
    _percents_len : felt,
    _percents : Uint256*,
    _percents_sum : Uint256,
    _array_index : felt,
):
    alloc_locals
    assert _unlocking_times_len = _percents_len

    if _unlocking_times_len == 0:
        return ()
    end

    local percent0 : Uint256 = _percents[0]
    vesting_portions_unlock_time_array.write(_array_index, _unlocking_times[0])
    # vesting_percent_per_portion_array.write(_array_index, _percents[0])
    vesting_percent_per_portion_array.write(_array_index, percent0)
    let (local percent_sum0 : Uint256) = uint256_checked_add(_percents_sum, percent0)
    return populate_vesting_params_rec(
        _unlocking_times_len=_unlocking_times_len - 1,
        _unlocking_times=_unlocking_times + 1,
        _percents_len=_percents_len - 1,
        _percents=_percents + Uint256.SIZE,
        _percents_sum=percent_sum0,
        _array_index=_array_index + 1,
    )
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
    only_admin()
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
    only_admin()
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
    )
    sale.write(upd_sale)
    return ()
end

@external
func set_registration_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _registration_time_starts : felt, _registration_time_ends : felt
):
    only_admin()
    let (the_sale) = sale.read()
    let (the_reg) = registration.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadIDOContract::set_registration_time Sale not created yet"):
        assert the_sale.is_created = TRUE
    end
    with_attr error_message(
            "ZkPadIDOContract::set_registration_time the regidtrstion start time is already set"):
        assert the_reg.registration_time_starts = 0
    end
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
    only_admin()
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
    only_admin()
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

@view
func get_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (the_reg) = registration.read()
    return (res=the_reg.registration_time_starts)
end

@external
func register_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256, account : felt
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

    let (adjusted_amount) = get_adjusted_amount(
        _amount=amount, _cap=the_sale.lottery_tickets_burn_cap
    )
    let (current_winning) = user_to_winning_lottery_tickets.read(account)
    let (new_winning) = draw_winning_tickets(tickets_burnt=adjusted_amount, account=account)
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
    )
    sale.write(upd_sale)

    user_registered.emit(user_address=account, winning_lottery_tickets=new_winning)
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
    only_admin()
    let (current_allocation) = ido_allocation.read()
    with_attr error_message("ZkPadIDOContract::calculate_allocation allocation arealdy calculated"):
        let (allocation_check : felt) = uint256_eq(current_allocation, Uint256(0, 0))
        assert allocation_check = FALSE
    end
    let (the_sale) = sale.read()

    # Compute the allocation : amount_of_tokens_to_sell / total_winning_tickets
    let (the_allocation, _) = uint256_checked_div_rem(
        the_sale.amount_of_tokens_to_sell, the_sale.total_winning_tickets
    )
    # with_attr error_message("ZkPadIDOContract::calculate_allocation calculation error"):
    #     assert the_allocation * the_sale.total_winning_tickets = the_sale.amount_of_tokens_to_sell
    # end
    ido_allocation.write(the_allocation)
    return ()
end

# this function will call the VRF and determine the number of winning tickets (if any)
func draw_winning_tickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tickets_burnt : Uint256, account : felt
) -> (res : Uint256):
    alloc_locals
    let (rnd) = get_random_number()
    const max_denominator = 18446744073709551615  # 0xffffffffffffffff
    let (max_uint) = _felt_to_uint(max_denominator)
    let (num : Uint256) = uint256_checked_mul(tickets_burnt, rnd)
    let (winning, _) = uint256_checked_div_rem(num, max_uint)
    return (res=winning)
end

func get_random_number{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    rnd : Uint256
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
    let (rnd) = _felt_to_uint(rnd_felt)
    return (rnd)
end

@external
func participate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, number_of_tokens : Uint256, amount_paid : Uint256
) -> (res : felt):
    alloc_locals
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
    with_attr error_message(
            "ZkPadIDOContract::participate Number of IDO tokens to purchase is zero"):
        let (number_tokens_check : felt) = uint256_lt(Uint256(0, 0), number_of_tokens)
        assert number_tokens_check = TRUE
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
    let (the_alloc) = ido_allocation.read()
    with_attr error_message(
            "ZkPadIDOContract::participate The IDO token allocation has not been calculated"):
        let (allocation_check : felt) = uint256_lt(Uint256(0, 0), the_alloc)
        assert allocation_check = TRUE
    end
    let (winning_tickets) = user_to_winning_lottery_tickets.read(account)
    with_attr error_message(
            "ZkPadIDOContract::participate account does not have any winning lottery tickets"):
        let (winning_tkts_check : felt) = uint256_lt(Uint256(0, 0), winning_tickets)
        assert winning_tkts_check = TRUE
    end
    let (max_tokens_to_purchase : Uint256) = uint256_checked_mul(winning_tickets, the_alloc)
    let (number_of_tokens_byuing, _) = uint256_checked_div_rem(amount_paid, the_sale.token_price)
    with_attr error_message(
            "ZkPadIDOContract::participate Amount paid does not cover the number of tokens"):
        let (is_tokens_buying_le_tokens) = uint256_le(number_of_tokens_byuing, number_of_tokens)
        assert is_tokens_buying_le_tokens = TRUE
    end
    with_attr error_message("ZkPadIDOContract::participate Can't buy more than maximum allocation"):
        let (is_tokens_buying_le_max) = uint256_le(number_of_tokens_byuing, max_tokens_to_purchase)
        assert is_tokens_buying_le_max = TRUE
    end

    # Updates
    let (local total_tokens_sum : Uint256) = uint256_checked_add(
        the_sale.total_tokens_sold, number_of_tokens_byuing
    )

    let (local total_raised_sum : Uint256) = uint256_checked_add(the_sale.total_raised, amount_paid)

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
    )
    sale.write(upd_sale)

    let new_purchase = Participation(
        amount_bought=number_of_tokens_byuing,
        amount_paid=amount_paid,
        time_participated=block_timestamp,
        is_portion_withdrawn_array=0,
    )
    user_to_participation.write(account, new_purchase)

    has_participated.write(account, TRUE)

    let (nbr_participants) = number_of_participants.read()
    let (local nbr_participants_sum : Uint256) = uint256_checked_add(
        nbr_participants, Uint256(low=1, high=0)
    )

    number_of_participants.write(nbr_participants_sum)

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

    return (res=TRUE)
end
