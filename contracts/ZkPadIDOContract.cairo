%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

from InterfaceAll import (IERC20, IAdmin)
from contracts.utils.constants import (TRUE, FALSE)

struct Sale:
    # Token being sold (interface)
    member token : felt
    # Is sale created (boolean)
    member is_created : felt
    # Are earnings withdrawn (boolean)
    member earnings_withdrawn : felt
    # Is leftover withdrawn (boolean)
    member leftover_withdrawn : felt
    # Have tokens been deposited (boolean)
    member tokens_deposited : felt
    # Address of sale owner
    member sale_owner : felt
    # Price of the token quoted (do we need this?)
    member token_price : felt
    # Amount of tokens to sell
    member amount_of_tokens_to_sell : felt
    # Total tokens being sold
    member total_tokens_sold : felt
    # Total Raised (what are using to track this?)
    member total_raised : felt
    # Sale end time
    member sale_end : felt
    # When tokens can be withdrawn
    member tokens_unlock_time : felt
end

struct Participation:
    member amount_bought : felt
    member amount_paid : felt
    member time_participated : felt
    member round_id : felt
    # bool[] --> do we need a length struct member? 
    # member is_portion_withdrawn_array : felt*
    # can't have arrays as members of the struct. This prevents the struct from being used as a storage variable return type (only fels is allowed)
    # need to find another way to 
end

struct Round:
    member start_time : felt
    member max_participation : felt
end

struct Registration:
    member registration_time_starts : felt
    member registration_time_ends : felt
    member number_of_registrants : felt
end

# Sale
@storage_var
func sale() -> (res : Sale):
end

# Registration
@storage_var
func registration() -> (res : Registration):
end

# Number of users participated in the sale. 
@storage_var
func number_of_participants() -> (res : felt):
end

# Array storing IDS of rounds (IDs start from 1, so they can't be mapped as array indexes
# round_ids_array.write(0,123)....(1,234)....etc --> i is the index of the array
@storage_var
func round_ids_array(i : felt) -> (res : felt):
end

# Mapping round Id to round
@storage_var
func round_id_to_round(round_id : felt) -> (res : Round):
end

# Mapping user to his participation
@storage_var
func user_to_participation(user_address : felt) -> (res : Participation):
end

# Mapping user to round for which he registered
@storage_var
func address_to_round_registered_for(user_address : felt) -> (res : felt):
end

# mapping user to is participated or not
@storage_var
func is_participated(user_address : felt) -> (res : felt):
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

# Added configurable round ID for staking round
@storage_var
func staking_round_id() -> (res : felt):
end

# Max vesting time shift
@storage_var
func max_vesting_time_shift() -> (res : felt):
end

# Registration deposit amount, which will be paid during the registration, and returned back during the participation.
@storage_var
func registration_deposit() -> (res : felt):
end

# Accounting total fees collected, after sale admin can withdraw this
@storage_var
func registration_fees() -> (res : felt):
end

@storage_var
func admin_contract_address() -> (res : felt):
end

func only_sale_owner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    let (the_sale) = sale.read()
    with_attr error_message("ZkPadIDOContract: only sale owner - restricted"):
        assert the_sale.sale_owner = caller
    end

    return()
end

func only_admin {syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (caller) = get_caller_address()
    
end



