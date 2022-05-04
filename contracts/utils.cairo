from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_mul
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.invoke import invoke

func uint256_is_zero{range_check_ptr}(v : Uint256) -> (yesno : felt):
    let (yesno : felt) = uint256_eq(v, Uint256(0, 0))
    return (yesno)
end

func uint256_mul_checked{range_check_ptr}(a : Uint256, b : Uint256) -> (product : Uint256):
    alloc_locals

    let (product, carry) = uint256_mul(a, b)
    let (in_range) = uint256_is_zero(carry)
    with_attr error_message("number too big"):
        assert in_range = 1
    end
    return (product)
end

func get_array{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        array_len : felt, array : felt*, mapping_ref : felt) -> ():

    let index = array_len - 1
    tempvar args = cast(new (syscall_ptr, pedersen_ptr, range_check_ptr, index), felt*)
    invoke(mapping_ref, 4, args)
    let syscall_ptr = cast([ap - 4], felt*)
    let pedersen_ptr = cast([ap - 3], HashBuiltin*)
    let range_check_ptr = [ap - 2]
    assert array[index] = [ap - 1]

    if index == 0:
        return ()
    end

    return get_array(array_len - 1, array, mapping_ref)
end
