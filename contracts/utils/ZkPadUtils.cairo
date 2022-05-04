%lang starknet

from openzeppelin.utils.constants import FALSE, TRUE
from starkware.cairo.common.uint256 import (ALL_ONES, Uint256, uint256_eq, uint256_add, uint256_mul, uint256_unsigned_div_rem)

func assert_is_boolean(x : felt):
    # x == 0 || x == 1
    assert ((x - 1) * x) = 0
    return ()
end

func get_is_equal(a : felt, b : felt) -> (res : felt):
    if a == b:
        return (TRUE)
    else:
        return (FALSE)
    end
end

func invert(x : felt) -> (res : felt):
    if x == TRUE:
        return (FALSE)
    else:
        assert x = FALSE
        return (TRUE)
    end
end

# Uint256 helper functions
#

func uint256_is_zero{range_check_ptr}(v : Uint256) -> (yesno : felt):
    let (yesno : felt) = uint256_eq(v, Uint256(0, 0))
    return (yesno)
end

func uint256_max() -> (res : Uint256):
    return (Uint256(low=ALL_ONES, high=ALL_ONES))
end

func uint256_mul_checked{range_check_ptr}(a : Uint256, b : Uint256) -> (product : Uint256):
    alloc_locals

    let (product, carry) = uint256_mul(a, b)
    let (in_range) = uint256_is_zero(carry)
    with_attr error_message("number too big"):
        assert in_range = TRUE
    end
    return (product)
end

func uint256_unsigned_div_rem_up{range_check_ptr}(a : Uint256, b : Uint256) -> (res : Uint256):
    alloc_locals

    let (q, r) = uint256_unsigned_div_rem(a, b)
    let (reminder_is_zero : felt) = uint256_is_zero(r)

    if reminder_is_zero == TRUE:
        return (q)
    else:
        let (rounded_up, oof) = uint256_add(q, Uint256(low=1, high=0))
        with_attr error_message("rounding overflow"):
            assert oof = 0
        end
        return (rounded_up)
    end
end