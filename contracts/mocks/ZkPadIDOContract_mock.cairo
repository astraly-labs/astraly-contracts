%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import get_block_timestamp

from openzeppelin.utils.constants import TRUE, FALSE

@storage_var
func ido_launch_date() -> (res : felt):
end

@storage_var
func claim_allocation_success() -> (res : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    # Setup IDO Contract Params
    let (block_timestamp : felt) = get_block_timestamp()
    ido_launch_date.write(block_timestamp)
    claim_allocation_success.write(TRUE)
    return ()
end

@view
func get_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (ido_date : felt) = ido_launch_date.read()
    return (ido_date)
end

@external
func set_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    let (block_timestamp : felt) = get_block_timestamp()
    ido_launch_date.write(block_timestamp - 1000)
    return ()
end

@external
func set_claim_success{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    success : felt
) -> ():
    claim_allocation_success.write(success)
    return ()
end

@external
func register_user{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256, account : felt, nb_quest : felt
) -> (res : felt):
    let (success) = claim_allocation_success.read()
    return (success)
end
