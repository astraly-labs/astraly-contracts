%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_check
from starkware.cairo.common.math import assert_nn_le, assert_not_zero

from openzeppelin.token.erc20.library import (
    ERC20_name,
    ERC20_symbol,
    ERC20_totalSupply,
    ERC20_decimals,
    ERC20_balanceOf,
    ERC20_allowance,
    ERC20_initializer,
    ERC20_approve,
    ERC20_increaseAllowance,
    ERC20_decreaseAllowance,
    ERC20_transfer,
    ERC20_transferFrom,
    ERC20_mint,
)

from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner, Ownable_get_owner
from starkware.starknet.common.syscalls import get_caller_address
from contracts.utils import or, get_is_equal

from openzeppelin.utils.constants import TRUE

@storage_var
func cap_() -> (res : Uint256):
end

@storage_var
func distribution_address() -> (res : felt):
end

@storage_var
func vault_address() -> (res : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt,
    symbol : felt,
    decimals : felt,
    initial_supply : Uint256,
    recipient : felt,
    owner : felt,
    _cap : Uint256,
    _distribution_address : felt,
):
    uint256_check(_cap)
    let (cap_valid) = uint256_le(_cap, Uint256(0, 0))
    assert_not_zero(1 - cap_valid)
    assert_not_zero(_distribution_address)
    ERC20_initializer(name, symbol, decimals)
    ERC20_mint(recipient, initial_supply)
    Ownable_initializer(owner)
    cap_.write(_cap)
    distribution_address.write(_distribution_address)
    return ()
end

#
# Getters
#

@view
func cap{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : Uint256):
    let (res : Uint256) = cap_.read()
    return (res)
end

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC20_name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC20_symbol()
    return (symbol)
end

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalSupply : Uint256
):
    let (totalSupply : Uint256) = ERC20_totalSupply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    decimals : felt
):
    let (decimals) = ERC20_decimals()
    return (decimals)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (balance : Uint256):
    let (balance : Uint256) = ERC20_balanceOf(account)
    return (balance)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining : Uint256) = ERC20_allowance(owner, spender)
    return (remaining)
end

#
# Externals
#

@external
func set_vault_address{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _vault_address : felt
):
    Ownable_only_owner()
    assert_not_zero(_vault_address)
    vault_address.write(_vault_address)
    return ()
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20_transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20_transferFrom(sender, recipient, amount)
    return (TRUE)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    ERC20_approve(spender, amount)
    return (TRUE)
end

@external
func increaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, added_value : Uint256
) -> (success : felt):
    ERC20_increaseAllowance(spender, added_value)
    return (TRUE)
end

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, subtracted_value : Uint256
) -> (success : felt):
    ERC20_decreaseAllowance(spender, subtracted_value)
    return (TRUE)
end

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt, amount : Uint256
):
    alloc_locals
    Authorized_only()
    let (totalSupply : Uint256) = ERC20_totalSupply()
    let (cap : Uint256) = cap_.read()
    let (local sum : Uint256, is_overflow) = uint256_add(totalSupply, amount)
    assert is_overflow = 0
    let (enough_supply) = uint256_le(sum, cap)
    assert_not_zero(enough_supply)
    ERC20_mint(to, amount)
    return (TRUE)
end

func Authorized_only{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (owner : felt) = Ownable_get_owner()
    let (xzkp_address : felt) = vault_address.read()
    let (caller : felt) = get_caller_address()

    let (is_owner : felt) = get_is_equal(owner, caller)
    let (is_vault : felt) = get_is_equal(xzkp_address, caller)

    with_attr error_message("ZkPadToken:: Caller should be owner or vault"):
        let (is_valid : felt) = or(is_vault, is_owner)
        assert is_valid = TRUE
    end

    return ()
end

func Authorized_only{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (owner : felt) = Ownable_get_owner()
    let (xzkp_address : felt) = vault_address.read()
    let (caller : felt) = get_caller_address()

    let (is_owner : felt) = get_is_equal(owner, caller)
    let (is_vault : felt) = get_is_equal(xzkp_address, caller)

    with_attr error_message("ZkPadToken:: Caller should be owner or vault"):
        let (is_valid : felt) = or(is_vault, is_owner)
        assert is_valid = TRUE
    end

    return ()
end
