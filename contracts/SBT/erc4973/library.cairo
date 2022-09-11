%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import Uint256, uint256_check
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import get_caller_address

from openzeppelin.utils.constants.library import IERC721_METADATA_ID
from openzeppelin.introspection.erc165.library import ERC165
from openzeppelin.security.safemath.library import SafeUint256

#
# Events
#

@event
func Transfer(from_ : felt, to : felt, tokenId : Uint256):
end

#
# Storage
#
@storage_var
func ERC4973_name() -> (name : felt):
end

@storage_var
func ERC4973_symbol() -> (symbol : felt):
end

@storage_var
func ERC4973_owners(token_id : Uint256) -> (owner : felt):
end

@storage_var
func ERC4973_balances(account : felt) -> (balance : Uint256):
end

@storage_var
func ERC4973_token_uri(token_id : Uint256) -> (token_uri : felt):
end

const IERC4973_ID = 1  # TODO: Compute

namespace ERC4973:
    func initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        name : felt, symbol : felt
    ):
        ERC4973_name.write(name)
        ERC4973_symbol.write(symbol)
        ERC165.register_interface(IERC4973_ID)
        ERC165.register_interface(IERC721_METADATA_ID)
        return ()
    end

    # Getters
    func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
        let (name) = ERC4973_name.read()
        return (name)
    end

    func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        symbol : felt
    ):
        let (symbol) = ERC4973_symbol.read()
        return (symbol)
    end

    func balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt
    ) -> (balance : Uint256):
        with_attr error_message("ERC4973: balance query for the zero address"):
            assert_not_zero(owner)
        end
        let (balance : Uint256) = ERC4973_balances.read(owner)
        return (balance)
    end

    func owner_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_id : Uint256
    ) -> (owner : felt):
        with_attr error_message("ERC4973: token_id is not a valid Uint256"):
            uint256_check(token_id)
        end
        let (owner) = ERC4973_owners.read(token_id)
        with_attr error_message("ERC4973: owner query for nonexistent token"):
            assert_not_zero(owner)
        end
        return (owner)
    end

    func token_uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_id : Uint256
    ) -> (token_uri : felt):
        let (exists) = _exists(token_id)
        with_attr error_message("ERC4973_Metadata: URI query for nonexistent token"):
            assert exists = TRUE
        end

        # if tokenURI is not set, it will return 0
        let (token_uri) = ERC4973_token_uri.read(token_id)
        return (token_uri)
    end

    #
    # Internals
    #

    func assert_only_token_owner{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        token_id : Uint256
    ):
        uint256_check(token_id)
        let (caller) = get_caller_address()
        let (owner) = owner_of(token_id)
        # Note `owner_of` checks that the owner is not the zero address
        with_attr error_message("ERC4973: caller is not the token owner"):
            assert caller = owner
        end
        return ()
    end

    func _exists{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_id : Uint256
    ) -> (res : felt):
        let (res) = ERC4973_owners.read(token_id)

        if res == 0:
            return (FALSE)
        else:
            return (TRUE)
        end
    end

    func _burn{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        token_id : Uint256
    ):
        alloc_locals
        assert_only_token_owner(token_id)

        with_attr error_message("ERC4973: token_id is not a valid Uint256"):
            uint256_check(token_id)
        end
        let (owner) = owner_of(token_id)

        # Decrease owner balance
        let (balance : Uint256) = ERC4973_balances.read(owner)
        let (new_balance : Uint256) = SafeUint256.sub_le(balance, Uint256(1, 0))
        ERC4973_balances.write(owner, new_balance)

        # Delete owner
        ERC4973_owners.write(token_id, 0)
        Transfer.emit(owner, 0, token_id)
        return ()
    end

    func _mint{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        from_ : felt, to : felt, token_id : Uint256, uri : felt
    ):
        with_attr error_message("ERC4973: token_id is not a valid Uint256"):
            uint256_check(token_id)
        end
        with_attr error_message("ERC4973: cannot mint to the zero address"):
            assert_not_zero(to)
        end

        # Ensures token_id is unique
        let (exists) = _exists(token_id)
        with_attr error_message("ERC4973: token already minted"):
            assert exists = FALSE
        end

        let (balance : Uint256) = ERC4973_balances.read(to)
        let (new_balance : Uint256) = SafeUint256.add(balance, Uint256(1, 0))
        ERC4973_balances.write(to, new_balance)
        ERC4973_owners.write(token_id, to)
        ERC4973_token_uri.write(token_id, uri)
        Transfer.emit(0, to, token_id)
        return ()
    end

    #
    # Externals
    #

    func _set_token_uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        token_id : Uint256, token_uri : felt
    ):
        uint256_check(token_id)
        let (exists) = _exists(token_id)
        with_attr error_message("ERC4973_Metadata: set token URI for nonexistent token"):
            assert exists = TRUE
        end

        ERC4973_token_uri.write(token_id, token_uri)
        return ()
    end
end
