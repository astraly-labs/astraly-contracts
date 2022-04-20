%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import get_block_timestamp

from openzeppelin.utils.constants import TRUE, FALSE
from InterfaceAll import IZkPadIDOContract

@storage_var
func ido_contract_addresses(id : felt) -> (address : felt):
end

@storage_var
func current_id() -> (id : felt):
end

@storage_var
func random_number_generator_address() -> (res : felt):
end

@view
func get_ido_launch_date{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        id : felt) -> (launch_date : felt):
    let (the_address : felt) = ido_contract_addresses.read(id)
    let (launch_date) = IZkPadIDOContract.get_ido_launch_date(contract_address=the_address)
    return (launch_date)
end

@view
func get_ido_address{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        id : felt) -> (address : felt):
    alloc_locals
    let (the_address : felt) = ido_contract_addresses.read(id)

    return (the_address)
end

@view
func get_random_number_generator_address{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (rnd_nbr_gen_adr) = random_number_generator_address.read()
    return (res = rnd_nbr_gen_adr)
end

@external
func create_ido{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(address : felt):
    alloc_locals
    let (_id) = current_id.read()
    ido_contract_addresses.write(_id, address)
    current_id.write(_id + 1)
    return ()
end

@external
func set_random_number_generator_address{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(rnd_nbr_gen_adr : felt):
    random_number_generator_address.write(rnd_nbr_gen_adr)
    return()
end
