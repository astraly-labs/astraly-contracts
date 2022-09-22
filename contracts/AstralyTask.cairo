// # SPDX-License-Identifier: AGPL-3.0-or-later

%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bool import TRUE
from starkware.starknet.common.syscalls import get_block_timestamp

from contracts.AstralyAccessControl import AstralyAccessControl

from InterfaceAll import IAstralyIDOContract, Registration

// # @title Yagi Task
// # @description Triggers `calculate_allocation` at the end of the registration phase
// # @author Astraly

//############################################
// #                 STORAGE                 ##
//############################################

@storage_var
func __lastExecuted() -> (lastExecuted: felt) {
}

@storage_var
func __idoContractAddress() -> (address: felt) {
}

//############################################
// #                 CONSTRUCTOR             ##
//############################################

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _ido_factory_address: felt
) {
    AstralyAccessControl.initializer(_ido_factory_address);
    return ();
}

//############################################
// #                 GETTERS                 ##
//############################################

@view
func lastExecuted{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    lastExecuted: felt
) {
    let (lastExecuted) = __lastExecuted.read();
    return (lastExecuted,);
}

//############################################
// #                  TASK                   ##
//############################################

@view
func probeTask{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    taskReady: felt
) {
    alloc_locals;

    let (address: felt) = __idoContractAddress.read();
    assert_not_zero(address);

    let (registration: Registration) = IAstralyIDOContract.get_registration(
        contract_address=address
    );

    let (block_timestamp: felt) = get_block_timestamp();
    let taskReady: felt = is_le(registration.registration_time_ends, block_timestamp);

    return (taskReady=taskReady);
}

@external
func executeTask{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    alloc_locals;
    let (taskReady: felt) = probeTask();
    with_attr error_message("AstralyTask::Task not ready") {
        assert taskReady = TRUE;
    }

    let (block_timestamp) = get_block_timestamp();
    __lastExecuted.write(block_timestamp);

    // Calculate Allocation
    let (ido_address: felt) = __idoContractAddress.read();
    IAstralyIDOContract.calculate_allocation(contract_address=ido_address);

    return ();
}

@external
func setIDOContractAddress{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt
) -> () {
    assert_not_zero(address);
    AstralyAccessControl.assert_only_owner();
    __idoContractAddress.write(address);
    return ();
}
