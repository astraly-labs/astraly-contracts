%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_check
from starkware.cairo.common.math import assert_nn_le, assert_not_zero

from contracts.Ownable_base import Ownable_initializer, Ownable_only_owner
from contracts.utils.constants import TRUE

from contracts.token.ERC1155_base import (
    ERC1155_initialize_batch
)

@storage_var
func idoStartDate() -> (res : Uint256):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _idoStartDate : Uint256):
    uint256_check(_idoStartDate)
    let (date_valid) = uint256_le(_idoStartDate, Uint256(0, 0))
    assert_not_zero(1 - date_valid)
    return ()
end

