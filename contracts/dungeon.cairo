%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (assert_nn_le, assert_nn)

# owner - The token ID of the dungeon which is used as an index
@storage_var
func dungeon_owner(token_id : felt) -> (address : felt):
end

# Set: Populates a dungeon owner's address by tokenId
@external
func set_token_id{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,
        range_check_ptr}(token_id : felt, address : felt):

    # Set the owner of this dungeon
    dungeon_owner.write(token_id, address)
    
    return ()
end

# Get: Reads the current metadata for a dungeon by tokenId
@view
func get_dungeon{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,
        range_check_ptr}(token_id : felt) -> (address : felt):
    let (address) = dungeon_owner.read(token_id)
    return (address)
end