%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

from fossil.contracts.starknet.FactsRegistry import Keccak256Hash

@storage_var
func _state_roots(block_number : felt) -> (keccak : Keccak256Hash):
end

@view
func get_state_root{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    block_number : felt
) -> (keccak : Keccak256Hash):
    let (hash : Keccak256Hash) = _state_roots.read(block_number)
    return (hash)
end

@external
func set_state_root{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    state_root_len : felt, state_root : felt*, block_number : felt
):
    tempvar keccak : Keccak256Hash = Keccak256Hash(state_root[0], state_root[1], state_root[2], state_root[3])

    _state_roots.write(block_number, keccak)
    return ()
end
