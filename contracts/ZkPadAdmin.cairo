%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_nn_le, assert_not_equal, assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE

# All admins array
@storage_var
func admins_array(i : felt) -> (res : felt):
end

@storage_var
func admins_array_len() -> (res : felt):
end

# mapping user to is admin or not flag
@storage_var
func is_admin_user(user_address : felt) -> (res : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,range_check_ptr}(
    _admins_len : felt,
    _admins : felt*
):
    populate_admins_rec(_admins_len, _admins, 1)
    return()
end

func populate_admins_rec{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _admins_array_len : felt,
    _admins_array : felt*,
    _array_index : felt
):
    alloc_locals
    if _admins_array_len == 0:
        return()
    end
    local admins0 = _admins_array[0]
    admins_array.write(_array_index, admins0)
    admins_array_len.write(_array_index)
    is_admin_user.write(admins0, TRUE)

    return populate_admins_rec(
        _admins_array_len = _admins_array_len - 1,
        _admins_array = _admins_array + 1,
        _array_index = _array_index + 1
    )
end

@view
func is_admin{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user_address : felt) -> (res : felt):
    let (the_user) = is_admin_user.read(user_address)
    return (res = the_user)
end

@view
func get_admins_array_len{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (the_length) = admins_array_len.read()
    return(res = the_length)
end
