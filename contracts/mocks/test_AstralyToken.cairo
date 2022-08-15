%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.token.erc20.library import ERC20
from contracts.AstralyAccessControl import AstralyAccessControl

from contracts.AstralyToken import constructor

@external
func burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, amount : Uint256
):
    AstralyAccessControl.assert_only_owner()
    ERC20._burn(account, amount)
    return ()
end
