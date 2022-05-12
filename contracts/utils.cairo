from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_mul
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.invoke import invoke

func uint256_is_zero{range_check_ptr}(v : Uint256) -> (yesno : felt):
    let (yesno : felt) = uint256_eq(v, Uint256(0, 0))
    return (yesno)
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

func and{syscall_ptr : felt*}(lhs : felt, rhs : felt) -> (res : felt):
    if lhs + rhs == 2:
        return (1)
    end
    return (0)
end

func or{syscall_ptr : felt*}(lhs : felt, rhs : felt) -> (res : felt):
    if (lhs-1) * (rhs-1) == 0:
        return (1)
    end
    return (0)
end
