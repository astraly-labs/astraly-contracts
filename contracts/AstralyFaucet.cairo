%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_block_number,
    get_block_timestamp,
    get_contract_address,
)

from contracts.AstralyAccessControl import AstralyAccessControl

from openzeppelin.token.erc20.IERC20 import IERC20

#
# Sorage
#
@storage_var
func faucet_unlock_time(user : felt) -> (unlock_time : felt):
end

@storage_var
func wait_time() -> (wait_time : felt):
end

@storage_var
func token_address() -> (address : felt):
end

@storage_var
func withdrawal_amount() -> (withdraw_value : Uint256):
end

#
# Getters
#

@view
func get_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : Uint256
):
    let (res : Uint256) = withdrawal_amount.read()
    return (res)
end

@view
func get_wait{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res : felt) = wait_time.read()
    return (res)
end

@view
func get_unlock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (res : felt):
    let (res : felt) = faucet_unlock_time.read(account)
    return (res)
end

#
# Setters
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, _token_address : felt, _withdrawal_amount : Uint256, _wait_time : felt
):
    AstralyAccessControl.initializer(owner)
    token_address.write(_token_address)
    withdrawal_amount.write(_withdrawal_amount)
    wait_time.write(_wait_time)

    return ()
end

@external
func set_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    amount : Uint256
) -> ():
    AstralyAccessControl.assert_only_owner()
    withdrawal_amount.write(amount)
    return ()
end

@external
func set_wait{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(wait : felt) -> ():
    AstralyAccessControl.assert_only_owner()
    wait_time.write(wait)
    return ()
end

#
# External
#

@external
func faucet_transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    success : felt
):
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (this_address : felt) = get_contract_address()
    let (withdraw_value : Uint256) = withdrawal_amount.read()
    let (_is_allowed : felt) = allowedToWithdraw(caller_address)
    if _is_allowed == TRUE:
        let (timestamp : felt) = get_block_timestamp()
        let (_wait_time : felt) = wait_time.read()
        faucet_unlock_time.write(caller_address, timestamp + _wait_time)
        let (token : felt) = token_address.read()
        let (success : felt) = IERC20.transfer(
            contract_address=token, recipient=caller_address, amount=withdraw_value
        )
        with_attr error_message("transfer failed"):
            assert success = TRUE
        end
        return (TRUE)
    end
    return (FALSE)
end

#
# View
#

@view
func allowedToWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
) -> (success : felt):
    alloc_locals
    let (_unlock_time : felt) = faucet_unlock_time.read(address)
    if _unlock_time == 0:
        return (TRUE)
    end
    let (timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = faucet_unlock_time.read(address)
    let (_is_valid : felt) = is_le(unlock_time, timestamp)
    if _is_valid == TRUE:
        return (TRUE)
    end
    return (FALSE)
end
