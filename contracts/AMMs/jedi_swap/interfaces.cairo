%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IJediSwapPair {
    func token0() -> (address: felt) {
    }

    func token1() -> (address: felt) {
    }

    func get_reserves() -> (reserve0: Uint256, reserve1: Uint256, block_timestamp_last: felt) {
    }

    func price_0_cumulative_last() -> (res: Uint256) {
    }

    func price_1_cumulative_last() -> (res: Uint256) {
    }

    func klast() -> (res: Uint256) {
    }

    func mint(to: felt) -> (liquidity: Uint256) {
    }

    func burn(to: felt) -> (amount0: Uint256, amount1: Uint256) {
    }

    func swap(amount0Out: Uint256, amount1Out: Uint256, to: felt, data_len: felt, data: felt*) {
    }

    func skim(to: felt) {
    }

    func sync() {
    }
}
