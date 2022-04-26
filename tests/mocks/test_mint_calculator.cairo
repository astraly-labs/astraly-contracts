%lang starknet

from starkware.cairo.common.uint256 import Uint256
 
@external
func getAmountToMint(input : Uint256) -> (amount : Uint256):
    return (input)
end
