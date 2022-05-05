%lang starknet

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.syscalls import get_caller_address, get_block_timestamp
from openzeppelin.token.erc20.library import ERC20_mint

from openzeppelin.utils.constants import TRUE,FALSE


const WAIT_TIME = 300

#je sais pas trop quelle valeur mettre

#store the next unlock time 
@storage_var 
func faucet_unlock_time(user : felt)->(unlock_time: felt)
end

@external
func faucet_transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (success: felt):
    let amount: Uint256 = Uint256(100000000)  #arbitrary value
    let (caller_address) = get_caller_address()
	if (allowedToWithdraw(caller_address)) : 
    		ERC20_mint(caller, amount)
		faucet_unlock_time.write(caller_address,get_block_timestamp + WAIT_TIME)
		return(TRUE)
	end
    return (FALSE)
end

@external 
func allowedToWithdraw{
	syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address : felt) -> (success :felt) : 
	if (faucet_unlock_time.read(address) == 0) :
		return(TRUE)
	end 
	if ( get_block_timestamp >=faucet_unlock_time.read(address)):
		return(TRUE)
	end 
	return(FALSE)
end 
    