%lang starknet

from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_mul, ALL_ONES
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.invoke import invoke
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy

from openzeppelin.security.safemath.library import SafeUint256

func uint256_is_zero{range_check_ptr}(v: Uint256) -> (yesno: felt) {
    let (yesno: felt) = uint256_eq(v, Uint256(0, 0));
    return (yesno,);
}

func uint256_max() -> (res: Uint256) {
    return (Uint256(low=ALL_ONES, high=ALL_ONES),);
}

func uint256_is_not_zero{range_check_ptr}(v: Uint256) -> (yesno: felt) {
    let (is_zero: felt) = uint256_eq(v, Uint256(0, 0));
    if (is_zero == TRUE) {
        return (FALSE,);
    } else {
        return (TRUE,);
    }
}

func uint256_mul_checked{range_check_ptr}(a: Uint256, b: Uint256) -> (product: Uint256) {
    alloc_locals;

    let (product, carry) = uint256_mul(a, b);
    let (in_range) = uint256_is_zero(carry);
    with_attr error_message("number too big") {
        assert in_range = 1;
    }
    return (product,);
}

func uint256_assert_not_zero{range_check_ptr}(value: Uint256) {
    let (is_zero: felt) = uint256_is_not_zero(value);
    assert is_zero = TRUE;
    return ();
}

// EXAMPLE
// @storage_var
// func array(index : felt) -> (value : felt):
// end

// @storage_var
// func array_length() -> (length : felt):
// end
func get_array{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: felt*, mapping_ref: felt*
) -> () {
    if (array_len == 0) {
        return ();
    }
    let index = array_len - 1;
    tempvar args: felt* = cast(new (syscall_ptr, pedersen_ptr, range_check_ptr, index), felt*);
    invoke(mapping_ref, 4, args);
    let syscall_ptr = cast([ap - 4], felt*);
    let pedersen_ptr = cast([ap - 3], HashBuiltin*);
    let range_check_ptr = [ap - 2];
    assert array[index] = [ap - 1];

    return get_array(array_len - 1, array, mapping_ref);
}

func concat_arr{range_check_ptr}(arr1_len: felt, arr1: felt*, arr2_len: felt, arr2: felt*) -> (
    res: felt*, res_len: felt
) {
    alloc_locals;
    let (local res: felt*) = alloc();
    memcpy(res, arr1, arr1_len);
    memcpy(res + arr1_len, arr2, arr2_len);
    return (res, arr1_len + arr2_len);
}

// EXAMPLE
// @storage_var
// func array(index : felt) -> (value : felt):
// end

// @storage_var
// func array_length() -> (length : felt):
// end

func write_to_array{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    array_len: felt, array: felt*, mapping_ref: felt*
) -> () {
    if (array_len == 0) {
        return ();
    }
    let index = array_len - 1;
    tempvar value_to_write = [array + index];
    tempvar args = cast(new (syscall_ptr, pedersen_ptr, range_check_ptr, index, value_to_write), felt*);
    invoke(mapping_ref, 5, args);
    let syscall_ptr = cast([ap - 3], felt*);
    let pedersen_ptr = cast([ap - 2], HashBuiltin*);
    let range_check_ptr = [ap - 1];

    return write_to_array(array_len - 1, array, mapping_ref);
}

func or{syscall_ptr: felt*}(lhs: felt, rhs: felt) -> (res: felt) {
    if ((lhs - 1) * (rhs - 1) == 0) {
        return (1,);
    }
    return (0,);
}

func is_lt{syscall_ptr: felt*, range_check_ptr}(lhs: felt, rhs: felt) -> (res: felt) {
    if (rhs == 0) {
        return (FALSE,);
    }
    let res: felt = is_le(lhs, rhs - 1);
    return (res,);
}

func mul_div_down{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    x: Uint256, y: Uint256, denominator: Uint256
) -> (res: Uint256) {
    alloc_locals;
    let (z: Uint256) = SafeUint256.mul(x, y);

    let (dominator_is_zero: felt) = uint256_is_zero(denominator);
    assert dominator_is_zero = FALSE;

    let (x_is_zero: felt) = uint256_is_zero(x);
    let (div: Uint256, _) = SafeUint256.div_rem(z, x);
    let (is_eq: felt) = uint256_eq(div, y);
    let (_or: felt) = or(x_is_zero, is_eq);
    assert _or = TRUE;

    let (res: Uint256, _) = SafeUint256.div_rem(z, denominator);
    return (res,);
}

func get_is_equal(a: felt, b: felt) -> (res: felt) {
    if (a == b) {
        return (TRUE,);
    } else {
        return (FALSE,);
    }
}
