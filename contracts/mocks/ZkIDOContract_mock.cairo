%lang starknet

from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import (
    get_block_timestamp 
)

@external
func get_ido_launch_date{syscall_ptr : felt*}() -> (res : felt):
    let (block_timestamp : felt) = get_block_timestamp()
    return (block_timestamp)
end

@external
func claim_allocation(amount: Uint256, account: felt) -> (res: felt):
    return (1)
end