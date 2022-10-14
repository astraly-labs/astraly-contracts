%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IJediswapwrapper {
    func get_pool_address() -> (address: felt) {
    }

    func get_token_price(amount: Uint256) -> (price: Uint256) {
    }
}
