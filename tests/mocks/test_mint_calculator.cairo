%lang starknet

from starkware.cairo.common.uint256 import Uint256
 
@external
func get_amount_to_mint(input : Uint256) -> (amount : Uint256):
    return (input)
end
