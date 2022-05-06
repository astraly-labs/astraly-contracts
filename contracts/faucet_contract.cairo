%lang starknet

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.syscalls import get_caller_address, get_block_timestamp
from openzeppelin.token.erc20.library import ERC20_mint
from starkware.cairo.common.math_cmp import is_le

from openzeppelin.utils.constants import TRUE,FALSE


#
#Sorage 
#
@storage_var 
func faucet_unlock_time(user : felt)->(unlock_time: felt) : 
end

@storage_var
func wait_time()->(wait_time : felt):
end 

@storage_var 
func withdrawal_amount()->(withdraw_value : felt):
end


#
#Getters
#

@view
func get_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res : felt) = withdrawal_amount.read()
    return (res)
end

@view
func get_wait{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res :felt):
    let (res : felt) = wait_time.read()
    return (res)
end

#
#Setters
#

@external 
func set_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount :felt)->() : 
	let (withdraw_amount : felt) = amount
	withdrawal_amount.write(withdraw_amount)
	return()
end

@external 
func set_wait{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(wait :felt)->() : 
	let (waiting : felt) = wait
	wait_time.write(waiting)
	return()
end

#
#External
#

@external
func faucet_transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (success: felt):
    let (caller_address) = get_caller_address()
	let ( withdraw_value: Uint256)  = withdrawal_amount.read()
	if (allowedToWithdraw(caller_address)) : 
    	let (timestamp: felt) = get_block_timestamp()
 		faucet_unlock_time.write(caller_address, timestamp + wait_time.read())
		return(TRUE)
	end
    return (FALSE)
end

#
#View
#

@view
func allowedToWithdraw{
	syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address : felt) -> (success :felt) : 
	if (faucet_unlock_time.read(address) == 0) :
		return(TRUE)
	end 
	let (timestamp: felt) = get_block_timestamp()
    let (unlock_time: felt) = faucet_unlock_time.read(address)
	if is_le(unlock_time, timestamp):
	     return (TRUE)
	end
	return (FALSE)
end 
    