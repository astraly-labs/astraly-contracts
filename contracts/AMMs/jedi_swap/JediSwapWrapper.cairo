%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.pow import pow

from openzeppelin.security.safemath.library import SafeUint256
from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.AMMs.jedi_swap.interfaces import IJediSwapPair

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
func get_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    address: felt
) {
    let (_pool_address: felt) = pool_address.read();
    return (_pool_address,);
}

@view
func get_token_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount: Uint256
) -> (price: Uint256) {
    alloc_locals;
    let (pool_address: felt) = get_pool_address();
    let (token1) = IJediSwapPair.token1(pool_address);
    let (reserve_token_0: Uint256, reserve_token_1: Uint256, _) = IJediSwapPair.get_reserves(
        pool_address
    );

    let (decimals) = IERC20.decimals(token1);
    let (local power) = pow(10, decimals);
    let (res0) = SafeUint256.mul(reserve_token_0, Uint256(power, 0));

    let (_price) = SafeUint256.mul(amount, res0);
    // amount of token0 needed to buy token1
    let (price, _) = SafeUint256.div_rem(_price, reserve_token_1);

    return (price,);
}
