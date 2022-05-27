%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_zero

from openzeppelin.security.safemath import (uint256_checked_mul, uint256_checked_div_rem)

from contracts.AMMs.alpha_road.interfaces import IARFPool

@storage_var
func pool_address() -> (address : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(pool : felt):
    assert_not_zero(pool)
    pool_address.write(pool)
    return ()
end

@view
func getPoolAddress{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (address : felt):
    let (pool_address : felt) = getPoolAddress()
    return (pool_address)
end


@view
func getAmountToMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_amount : Uint256) -> (amount : Uint256):
    alloc_locals
    let (pool_address : felt) = getPoolAddress()
    let (_, _, _, total_supply: Uint256, _, _, reserve_token_0: Uint256, reserve_token_1: Uint256) = IARFPool.getBatchInfos(pool_address)
    let (mul : Uint256) = uint256_checked_mul(lp_amount, reserve_token_1) # TODO: Check the order of the pairs
    let (res : Uint256, _) = uint256_checked_div_rem(mul, total_supply)

    return (res)
end
