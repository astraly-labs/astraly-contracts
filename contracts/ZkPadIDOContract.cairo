%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn_le, assert_not_equal, assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc

from InterfaceAll import (IAdmin, IZKPadIDOFactory, IZkStakingVault, IXoroshiro, XOROSHIRO_ADDR)
from contracts.utils.ZkPadConstants import (DAYS_30)
from contracts.utils.ZkPadUtils import get_is_equal
from starkware.starknet.common.syscalls import (get_block_timestamp)
from openzeppelin.utils.constants import FALSE, TRUE
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20

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
    member token_price : felt
    # Amount of tokens to sell
    member amount_of_tokens_to_sell : felt
    # Total tokens being sold
    member total_tokens_sold : felt
    # Total winning lottery tickets
    member total_winning_tickets : felt
    # Total Raised (what are using to track this?)
    member total_raised : felt
    # Sale end time
    member sale_end : felt
    # When tokens can be withdrawn
    member tokens_unlock_time : felt
    # Cap on the number of lottery tickets to burn when registring
    member lottery_tickets_burn_cap : felt
end

struct Participation:
    member amount_bought : felt
    member amount_paid : felt
    member time_participated : felt
    # member round_id : felt
    member is_portion_withdrawn_array : felt # can't have arrays as members of the struct. Will use a felt with a bit mask
end

struct Registration:
    member registration_time_starts : felt
    member registration_time_ends : felt
    member number_of_registrants : felt
end

struct Purchase_Round:
    member time_starts : felt
    member time_ends : felt
    member number_of_purchases : felt
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
func number_of_participants() -> (res : felt):
end

# Mapping user to his participation
@storage_var
func user_to_participation(user_address : felt) -> (res : Participation):
end

# Mapping user to number of winning lottery tickets
@storage_var
func user_to_winning_lottery_tickets(user_address : felt) -> (res : felt):
end

# Mapping user to number of allocations
@storage_var
func address_to_allocations(user_address : felt) -> (res : felt):
end

# total allocations given
@storage_var
func total_allocations_given() -> (res : felt):
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
func vesting_percent_per_portion_array(i :felt) -> (res : felt):
end

# Precision for percent for portion vesting
@storage_var
func portion_vesting_precision() -> (res : felt):
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
func ido_allocation() -> (res : felt):
end

func only_sale_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (the_sale) = sale.read()
    with_attr error_message("ZkPadIDOContract: only sale owner can call this function"):
        assert the_sale.sale_owner = caller
    end

    return()
end

func only_admin {syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (the_admin_address) = admin_contract_address.read()
    let (is_admin) = IAdmin.is_admin(contract_address=the_admin_address, user_address=caller)
    with_attr error_message("ZkPadIDOContract: only sale admin can call this function"):
        assert is_admin = 1
    end

    return()
end

@event
func tokens_sold(user_address : felt, amount : felt):
end

@event 
func user_registered(user_address : felt, winning_lottery_tickets : felt):
end

@event
func token_price_set(new_price : felt):
end

@event
func tokens_withdrawn(user_address : felt, amount : felt):
end

@event
func sale_created(
    sale_owner_address : felt,
    token_price : felt,
    amount_of_tokens_to_sell : felt,
    sale_end : felt,
    tokens_unlock_time : felt
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
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _admin_address : felt,
    _staking_vault_address : felt,
    _ido_factory_contract_address : felt
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
func set_vesting_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times     : felt*,
    _percents_len        : felt,
    _percents            : felt*,
    _max_vesting_time_shift : felt
):
    alloc_locals
    only_admin()

    with_attr error_message("ZkPadIDOContract::set_vesting_params unlocking times array length 0"):
        assert_not_zero(_unlocking_times_len)
    end
    with_attr error_message("ZkPadIDOContract::set_vesting_params percents array length 0"):
        assert_not_zero(_percents_len)
    end
    with_attr error_message("ZkPadIDOContract::set_vesting_params unlocking times and percents arrays different lengths"):
        assert _unlocking_times_len = _percents_len
    end
    
    let (_portion_vesting_precision) = portion_vesting_precision.read()
    with_attr error_message("ZkPadIDOContract::set_vesting_params portion vesting precision is zero"):
        assert_lt(0, _portion_vesting_precision)
    end

    with_attr error_message("ZkPadIDOContract::set_vesting_params max vesting time shift more than 30 days"):
        assert_le(_max_vesting_time_shift, DAYS_30)
    end
    
    max_vesting_time_shift.write(_max_vesting_time_shift)

    local percent_sum = 0
    local array_index = 0
    
    populate_vesting_params_rec(
        _unlocking_times_len,
        _unlocking_times,
        _percents_len,
        _percents,
        percent_sum,
        array_index
    )

    with_attr error_message("ZkPadIDOContract::set_vesting_params Percent distribution issue"):
        assert percent_sum = _portion_vesting_precision
    end

    return()
end

func populate_vesting_params_rec{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _unlocking_times_len : felt,
    _unlocking_times     : felt*,
    _percents_len        : felt,
    _percents            : felt*,
    _percents_sum        : felt, 
    _array_index         : felt
):
    alloc_locals
    assert _unlocking_times_len = _percents_len
    
    if _unlocking_times_len == 0:
        return ()
    end

    local percent0 = _percents[0]
    vesting_portions_unlock_time_array.write(_array_index, _unlocking_times[0])
    # vesting_percent_per_portion_array.write(_array_index, _percents[0])
    vesting_percent_per_portion_array.write(_array_index, percent0)

    return populate_vesting_params_rec(
        _unlocking_times_len = _unlocking_times_len - 1,
        _unlocking_times = _unlocking_times + 1,
        _percents_len =_percents_len - 1,
        _percents = _percents + 1,
        _percents_sum = _percents_sum + percent0,    #_percents_sum = _percents_sum + _percents[0],
        _array_index = _array_index + 1
    )
end

@external
func set_sale_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr} (
    _token_address : felt,
    _sale_owner_address : felt,
    _token_price : felt,
    _amount_of_tokens_to_sell : felt,
    _sale_end_time : felt,
    _tokens_unlock_time : felt,
    _portion_vesting_precision : felt,
    _lottery_tickets_burn_cap : felt
):
    # alloc_locals
    only_admin()
    let (the_sale) = sale.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadIDOContract::set_sale_params Sale is already created"):
        assert the_sale.is_created = FALSE
    end
    with_attr error_message("ZkPadIDOContract::set_sale_params Sale owner address can not be 0"):
        assert_not_zero(_sale_owner_address)
    end
    with_attr error_message("ZkPadIDOContract::set_sale_params Bad input"):
        assert_not_zero(_token_price)
        assert_not_zero(_amount_of_tokens_to_sell)
        assert_lt(block_timestamp, _sale_end_time)
        assert_lt(block_timestamp, _tokens_unlock_time)
    end
    with_attr error_message("ZkPadIDOContract::set_sale_params portion vesting percision should be at least 100"):
        assert_le(100, _portion_vesting_precision)
    end

    # set params
    let new_sale = Sale(
        token = _token_address,
        is_created = TRUE,
        raised_funds_withdrawn = FALSE,
        leftover_withdrawn = FALSE,
        tokens_deposited = 0,
        sale_owner = _sale_owner_address,
        token_price = _token_price,
        amount_of_tokens_to_sell = _amount_of_tokens_to_sell,
        total_tokens_sold = 0,
        total_winning_tickets = 0,
        total_raised = 0,
        sale_end = _sale_end_time,
        tokens_unlock_time = _tokens_unlock_time,
        lottery_tickets_burn_cap = _lottery_tickets_burn_cap
    )
    sale.write(new_sale)
    # Set portion vesting precision
    portion_vesting_precision.write(_portion_vesting_precision)
    # emit event
    sale_created.emit(
        sale_owner_address = _sale_owner_address,
        token_price = _token_price,
        amount_of_tokens_to_sell = _amount_of_tokens_to_sell,
        sale_end = _sale_end_time,
        tokens_unlock_time = _tokens_unlock_time
    )
    return()
end

@external
func set_sale_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(_sale_token_address : felt):
    only_admin()
    let (the_sale) = sale.read()
    let upd_sale = Sale(
        token = _sale_token_address,
        is_created = the_sale.is_created,
        raised_funds_withdrawn = the_sale.raised_funds_withdrawn,
        leftover_withdrawn = the_sale.leftover_withdrawn,
        tokens_deposited = the_sale.tokens_deposited,
        sale_owner = the_sale.sale_owner,
        token_price = the_sale.token_price,
        amount_of_tokens_to_sell = the_sale.amount_of_tokens_to_sell,
        total_tokens_sold = the_sale.total_tokens_sold,
        total_winning_tickets = the_sale.total_winning_tickets,
        total_raised = the_sale.total_raised,
        sale_end = the_sale.sale_end,
        tokens_unlock_time = the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap = the_sale.lottery_tickets_burn_cap
    )
    sale.write(upd_sale)
    return()
end

@external
func set_registration_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _registration_time_starts : felt,
    _registration_time_ends : felt
):
    only_admin()
    let (the_sale) = sale.read()
    let (the_reg) = registration.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadIDOContract::set_registration_time Sale not created yet"):
        assert the_sale.is_created = TRUE
    end
    with_attr error_message("ZkPadIDOContract::set_registration_time the regidtrstion start time is already set"):
        assert the_reg.registration_time_starts = 0
    end
    with_attr error_message("ZkPadIDOContract::set_registration_time registration start/end times issue"):
        assert_le(block_timestamp, _registration_time_starts)
        assert_lt(_registration_time_starts, _registration_time_ends)
    end
    with_attr error_message("ZkPadIDOContract::set_registration_time registration end has to be before sale end"):
        assert_lt(_registration_time_ends, the_sale.sale_end)
    end
    let upd_reg = Registration(
        registration_time_starts = _registration_time_starts,
        registration_time_ends = _registration_time_ends,
        number_of_registrants = the_reg.number_of_registrants
    )
    registration.write(upd_reg)
    registration_time_set.emit(
        registration_time_starts = _registration_time_starts, 
        registration_time_ends = _registration_time_ends
    )
    return()
end

@external
func set_purchase_round_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _purchase_time_starts : felt,
    _purchase_time_ends : felt
):
    only_admin()
    let (the_reg) = registration.read()
    let (the_purchase) = purchase_round.read()
    with_attr error_message("ZkPadIDOContract::set_purchase_round_params Bad input"):
        assert_not_zero(_purchase_time_starts)
        assert_not_zero(_purchase_time_ends)
    end
    with_attr error_message("ZkPadIDOContract::set_purchase_round_params end time must be after start end"):
        assert_lt(_purchase_time_starts, _purchase_time_ends)
    end
    with_attr error_message("ZkPadIDOContract::set_purchase_round_params registration time not set yet"):
        assert_not_zero(the_reg.registration_time_starts)
        assert_not_zero(the_reg.registration_time_ends)
    end 
    with_attr error_message("ZkPadIDOContract::set_purchase_round_params start time must be after registration end"):
        assert_lt(the_reg.registration_time_ends, _purchase_time_starts)
    end
    let upd_purchase = Purchase_Round(
        time_starts = _purchase_time_starts,
        time_ends = _purchase_time_ends,
        number_of_purchases = the_purchase.number_of_purchases
    )
    purchase_round.write(upd_purchase)
    purchase_round_time_set.emit(
        purchase_time_starts = _purchase_time_starts, 
        purchase_time_ends = _purchase_time_ends)
    return()
end

@external
func set_dist_round_params{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
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
    with_attr error_message("ZkPadIDOContract::set_dist_round_params Disctribtion must start after purchase round ends"):
        assert_lt(the_purchase.time_ends, _dist_time_starts)
    end
    let upd_dist = Distribution_Round(
        time_starts = _dist_time_starts
    )
    disctribution_round.write(upd_dist)
    distribtion_round_time_set.emit(dist_time_starts = _dist_time_starts)
    return()
end

@view
func get_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (res : felt):
    let (the_reg) = registration.read()
    return(res = the_reg.registration_time_starts)
end

@external
func register_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount: felt, account: felt) -> (res: felt):
    alloc_locals
    let (the_reg) = registration.read()
    let (block_timestamp) = get_block_timestamp()
    let (the_sale) = sale.read()
    
    let (factory_address) = ido_factory_contract_address.read()
    let (lottery_ticket_address) = IZKPadIDOFactory.get_lottery_ticket_contract_address(contract_address=factory_address)
    with_attr error_message("ZkPadIDOContract::register_user Lottery ticket contract address not set"):
        assert_not_zero(lottery_ticket_address)
    end
    let (caller) = get_caller_address()
    with_attr error_message("ZkPadIDOContract::register_user only the lottery ticket contract can make this call"):
        assert caller = lottery_ticket_address
    end

    with_attr error_message("ZkPadIDOContract::register_user account address is the zero address"):
        assert_not_zero(account)
    end
    with_attr error_message("ZkPadIDOContract::register_user allocation claim amount not greater than 0"):
        assert_lt(0, amount)
    end
    with_attr error_message("ZkPadIDOContract::register_user Registration window is closed"):
        assert_le(the_reg.registration_time_starts, block_timestamp)
        assert_le(block_timestamp, the_reg.registration_time_ends)
    end

    let (is_user_reg) = is_registered.read(account)
    if is_user_reg == 0:
        is_registered.write(account, TRUE)
        let upd_reg = Registration(
            registration_time_starts = the_reg.registration_time_starts,
            registration_time_ends = the_reg.registration_time_ends,
            number_of_registrants = the_reg.number_of_registrants + 1
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

    let (adjusted_amount) = get_adjusted_amount(_amount=amount, _cap=the_sale.lottery_tickets_burn_cap)
    let (current_winning) = user_to_winning_lottery_tickets.read(account)
    let (new_winning) = draw_winning_tickets(tickets_burnt=adjusted_amount, account=account)
    user_to_winning_lottery_tickets.write(account, current_winning + new_winning)

    let upd_sale = Sale(
        token = the_sale.token,
        is_created = the_sale.is_created,
        raised_funds_withdrawn = the_sale.raised_funds_withdrawn,
        leftover_withdrawn = the_sale.leftover_withdrawn,
        tokens_deposited = the_sale.tokens_deposited,
        sale_owner = the_sale.sale_owner,
        token_price = the_sale.token_price,
        amount_of_tokens_to_sell = the_sale.amount_of_tokens_to_sell,
        total_tokens_sold = the_sale.total_tokens_sold,
        total_winning_tickets = the_sale.total_winning_tickets + new_winning,
        total_raised = the_sale.total_raised,
        sale_end = the_sale.sale_end,
        tokens_unlock_time = the_sale.tokens_unlock_time,
        lottery_tickets_burn_cap = the_sale.lottery_tickets_burn_cap
    )
    sale.write(upd_sale)

    user_registered.emit(user_address=account, winning_lottery_tickets=new_winning)
    return(res=TRUE)
end

func get_adjusted_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(_amount : felt, _cap) -> (res : felt):
    let (is_amount_le_cap) = is_le(_amount, _cap)
    if  is_amount_le_cap == TRUE:
        return (res=_amount)
    else:
        return (res=_cap)
    end
end

# This function will calculate allocation (USD/IDO Token) and will be triggered using the keeper network
# does this method need anu inputs? or will it only use the number of users and winning tickets?
@external
func calculate_allocation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}():
    only_admin()
    let (current_allocation) = ido_allocation.read()
    with_attr error_message("ZkPadIDOContract::calculate_allocation allocation arealdy calculated"):
        assert current_allocation = 0
    end
    let (the_sale) = sale.read()

    # Compute the allocation : total_tokens_sold / total_winning_tickets
    let (the_allocation, _) = unsigned_div_rem(the_sale.total_tokens_sold, the_sale.total_winning_tickets)
    with_attr error_message("ZkPadIDOContract::calculate_allocation calculation error"):
        assert the_allocation * the_sale.total_winning_tickets = the_sale.total_tokens_sold
    end
    ido_allocation.write(the_allocation)
    return()
end

# this function will call the VRF and determine the number of winning tickets (if any)
# for now will return the same number as burnt tickets. i.e. all tickets are winners!
func draw_winning_tickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(tickets_burnt: felt, account: felt) -> (res: felt):
    let (rnd) = get_random_number()
    # do something with this random number to come up with the number of winning tickets.
    return (res=tickets_burnt)
end

func get_random_number{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}() -> (rnd : felt):
    let (ido_factory_address) = ido_factory_contract_address.read()
    let (rnd_nbr_gen_addr) = IZKPadIDOFactory.get_random_number_generator_address(contract_address=ido_factory_address)
    with_attr error_message("ZkPadIDOContract::get_random_number random number generator address not set in the factory"):
        assert_not_zero(rnd_nbr_gen_addr)
    end
    let (rnd) = IXoroshiro.next(contract_address=rnd_nbr_gen_addr)
    with_attr error_message("ZkPadIDOContract::get_random_number invalid random number value"):
        assert_not_zero(rnd)
    end
    return (rnd)
end

# TODO: 1) Function to handle users who have guaranteed allocation (HOLD)
# TODO: 2) Add Maximum Allocation to prevent whales from abusing the system