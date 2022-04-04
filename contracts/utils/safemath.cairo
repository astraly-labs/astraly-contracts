from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_sub

func sub256{range_check_ptr}(lhs : Uint256, rhs : Uint256) -> (
        res : Uint256):
    let (safe : felt) = uint256_le(rhs, lhs)
    assert safe = 1
    let (res : Uint256 ) = uint256_sub(lhs, rhs)
    return (res)
end
