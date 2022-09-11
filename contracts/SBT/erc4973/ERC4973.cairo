%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_equal
from starkware.starknet.common.syscalls import get_caller_address

from openzeppelin.introspection.erc165.library import ERC165

from contracts.SBT.erc4973.library import ERC4973

#
# Getters
#

@view
func supportsInterface{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    interfaceId : felt
) -> (success : felt):
    let (success) = ERC165.supports_interface(interfaceId)
    return (success)
end

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC4973.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC4973.symbol()
    return (symbol)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt) -> (
    balance : Uint256
):
    let (balance : Uint256) = ERC4973.balance_of(owner)
    return (balance)
end

@view
func ownerOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    tokenId : Uint256
) -> (owner : felt):
    let (owner : felt) = ERC4973.owner_of(tokenId)
    return (owner)
end


#
# Externals
#
@external
func unequip{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    tokenId : Uint256
):
    ERC4973._burn(tokenId)
    return ()
end

@external
func give{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    to : felt, uri : felt, signature_len : felt, signature : felt*
) -> (res : Uint256):

    let (caller : felt) = get_caller_address()
    let tokenId : Uint256 = Uint256(0, 0)
    with_attr error_mesage("give: cannot give from self"):
        assert_not_equal(caller, to)
    end

    ERC4973._mint(caller, to, tokenId, uri)
    return (tokenId)
end

@external
func take{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    from_ : felt, uri : felt, signature_len : felt, signature : felt*
) -> (res : Uint256):
    let tokenId : Uint256 = Uint256(0, 0)
    let (caller : felt) = get_caller_address()
    ERC4973._mint(from_, caller, tokenId, uri)
    return (tokenId)
end
