%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.pow import pow
from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_le
from starkware.cairo.common.bool import TRUE
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address

from openzeppelin.token.erc20.library import ERC20
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20

from contracts.utils import uint256_is_zero, or, mul_div_down
from openzeppelin.security.safemath import SafeUint256

@storage_var
func underlying_address() -> (address : felt):
end

@storage_var
func base_unit() -> (unit : Uint256):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    underlying : felt
):
    alloc_locals
    underlying_address.write(underlying)
    let (decimals : felt) = IERC20.decimals(underlying)
    let (asset_base_unit : felt) = pow(10, decimals)
    base_unit.write(Uint256(asset_base_unit, 0))
    return ()
end

@view
func underlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (res : felt) = underlying_address.read()
    return (res)
end

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(amount : Uint256) -> (
    res : Uint256
):
    alloc_locals
    let (_base_unit : Uint256) = base_unit.read()
    let (mul : Uint256) = SafeUint256.mul(amount, _base_unit)
    let (exchange_rate : Uint256) = exchangeRate()
    let (amount_to_mint : Uint256) = mul_div_down(amount, _base_unit, exchange_rate)

    let (caller : felt) = get_caller_address()
    ERC20._mint(caller, amount_to_mint)
    let (address_this : felt) = get_contract_address()
    let (_underlying : felt) = underlying()
    IERC20.transferFrom(_underlying, caller, address_this, amount)
    return (amount_to_mint)
end

@external
func redeemUnderlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256
) -> (res : Uint256):
    alloc_locals
    let (_underlying : felt) = underlying()
    let (address_this : felt) = get_contract_address()
    let (underlying_balance_of_this : Uint256) = IERC20.balanceOf(_underlying, address_this)
    let (not_over_balance : felt) = uint256_le(amount, underlying_balance_of_this)
    assert not_over_balance = TRUE

    let (caller : felt) = get_caller_address()
    IERC20.transfer(_underlying, caller, amount)

    return (amount)
end

@external
func balanceOfUnderlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(user : felt) -> (
    res : Uint256
):
    let (_underlying : felt) = underlying()
    let (address_this : felt) = get_contract_address()
    let (balance_of_this : Uint256) = IERC20.balanceOf(_underlying, address_this)
    return (balance_of_this)
end

@external
func similateLoss{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    underlying_amount : Uint256
):
    let (_underlying : felt) = underlying()
    IERC20.transfer(_underlying, 0, underlying_amount)
    return ()
end

func exchangeRate{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Uint256
):
    alloc_locals
    let (total_supply : Uint256) = ERC20.total_supply()
    let (supply_is_zero : felt) = uint256_is_zero(total_supply)
    let (_base_unit : Uint256) = base_unit.read()
    if supply_is_zero == TRUE:
        return (_base_unit)
    end
    let (address_this : felt) = get_contract_address()
    let (_underlying : felt) = underlying()
    let (underlying_balance_of_this : Uint256) = IERC20.balanceOf(_underlying, address_this)

    let (res : Uint256) = mul_div_down(underlying_balance_of_this, _base_unit, total_supply)
    return (res)
end
