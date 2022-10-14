%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

@view
func get_token_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount: Uint256
) -> (price: Uint256) {
    // 1 Token = 1 Payment Token
    return (price=amount,);
}
