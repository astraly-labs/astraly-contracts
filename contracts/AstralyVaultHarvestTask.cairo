%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bool import TRUE
from starkware.starknet.common.syscalls import get_block_timestamp

from contracts.AstralyAccessControl import AstralyAccessControl

from InterfaceAll import IVault

# # @title Yagi Task
# # @description
# # @author Astraly

@storage_var
func __lastExecuted() -> (lastExecuted : felt):
end

@storage_var
func __vaultAddress() -> (address : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _vault_address : felt
):
    assert_not_zero(_vault_address)
    __vaultAddress.write(_vault_address)
    AstralyAccessControl.initializer(_vault_address)
    return ()
end

#############################################
# #                 GETTERS                 ##
#############################################

@view
func lastExecuted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    lastExecuted : felt
):
    let (lastExecuted) = __lastExecuted.read()
    return (lastExecuted)
end

@view
func probeTask{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    taskReady : felt
):
    alloc_locals
    let (vault_address : felt) = __vaultAddress.read()
    let (can_harvest : felt) = IVault.canHarvest(vault_address)
    return (can_harvest)
end

#############################################
# #                  TASK                   ##
#############################################

@external
func executeTask{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    alloc_locals
    let (taskReady : felt) = probeTask()
    with_attr error_message("AstralyTask::Task not ready"):
        assert taskReady = TRUE
    end

    let (block_timestamp) = get_block_timestamp()
    __lastExecuted.write(block_timestamp)

    let (vault_address : felt) = __vaultAddress.read()
    let (strategies_len : felt, strategies : felt*) = IVault.getWithdrawalStack(vault_address)
    IVault.harvest(vault_address, strategies_len, strategies)
    return ()
end
