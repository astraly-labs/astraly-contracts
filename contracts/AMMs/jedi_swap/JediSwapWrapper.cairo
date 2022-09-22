%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_zero

from openzeppelin.security.safemath.library import SafeUint256

from contracts.AMMs.jedi_swap.interfaces import IJediSwapPair

from InterfaceAll import IERC20

@storage_var
func pool_address() -> (address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(pool: felt) {
    assert_not_zero(pool);
    pool_address.write(pool);
    return ();
}

@view
func getPoolAddress{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    address: felt
) {
    let (_pool_address: felt) = pool_address.read();
    return (_pool_address,);
}

@view
func getAmountToMint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    lp_amount: Uint256
) -> (amount: Uint256) {
    alloc_locals;
    let (pool_address: felt) = getPoolAddress();
    let (reserve_token_0: Uint256, reserve_token_1: Uint256, _) = IJediSwapPair.get_reserves(
        pool_address
    );
    let (total_supply: Uint256) = IERC20.totalSupply(pool_address);
    let (mul: Uint256) = SafeUint256.mul(lp_amount, reserve_token_1);  // TODO: Check the order of the pairs
    let (res: Uint256, _) = SafeUint256.div_rem(mul, total_supply);

    return (res,);
}
