%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (Uint256, uint256_add, uint256_le, uint256_lt, uint256_check)
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address, get_block_number, get_block_timestamp
)

from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner
from openzeppelin.utils.constants import (TRUE, FALSE)

from contracts.token.ERC1155_struct import TokenUri

from contracts.token.ERC1155_base import (
    ERC1155_initializer,
    ERC1155_uri,
    ERC1155_safeTransferFrom,
    ERC1155_safeBatchTransferFrom,
    ERC1155_mint,
    ERC1155_mint_batch,
    ERC1155_burn,
    ERC1155_burn_batch,
    ERC1155_setApprovalForAll,
    ERC1155_balanceOf,
    ERC1155_balanceOfBatch,
    ERC1155_isApprovedForAll,
    ERC1155_supportsInterface,

    owner_or_approved
)

from InterfaceAll import (IZkIDOContract, IERC20, IERC4626)

@storage_var
func ido_contract_address() -> (res : felt):
end

@storage_var
func xzkp_contract_address() -> (res : felt):
end

@storage_var
func ido_launch_date() -> (res : felt):
end

@storage_var
func has_claimed(user: felt) -> (res : felt):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(uri: felt, owner : felt, _ido_contract_address : felt):
    # Initialize Admin
    assert_not_zero(owner)
    Ownable_initializer(owner)
    # Initialize ERC1155
    ERC1155_initializer(uri)
    # Setup IDO Contract Params
    assert_not_zero(_ido_contract_address)
    ido_contract_address.write(_ido_contract_address)
    _set_ido_launch_date()
    return ()
end

#
# Getters
#

@view
func supportsInterface(interfaceId : felt) -> (is_supported : felt):
    return ERC1155_supportsInterface(interfaceId)
end

# @dev Returns the URI for all token types
@view
func uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}()
        -> (uri : felt):
    return ERC1155_uri()
end

# @dev Returns the amount of tokens of token type token_id owned by owner
# @param owner : The address of the owner
# @param token_id : The id of the token
@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, id : Uint256) -> (balance : Uint256):
    return ERC1155_balanceOf(account,id)
end

# @dev Batched version of balanceOf.
# @param owners_len : The length of the owners array
# @param owners : the array of owner addresses
# @param tokens_id_len : the length of the toked ids array
# @param tokens_id : the array of token ids
@view
func balanceOfBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*)
        -> (balances_len : felt, balances : Uint256*):
    return ERC1155_balanceOfBatch(accounts_len,accounts,ids_len,ids)
end

# @dev Returns true if operator is approved to transfer account's tokens.
# @param operator : The address of the operator
# @param account : The address of the account
@view
func isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt, operator : felt) -> (is_approved : felt):
    return ERC1155_isApprovedForAll(account, operator)
end

#
# Externals
#

# @dev Sets the URI for all token types
# @param uri_ : The TokenUri to use . See the ERC1155_struct for more details about the TokenUri type.
# @external
# func setURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(uri_ : TokenUri):
#     ERC1155_uri_.write(uri_)

#     return ()
# end

# @dev Grants or revokes permission to operator to transfer the caller’s tokens, according to approved
# @param operator : The address of the opertor
# @param approved : Must be 0 (revoke) or 1 (grant)
@external
func setApprovalForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        operator : felt, approved : felt):
    ERC1155_setApprovalForAll(operator, approved)
    return ()
end

# @dev Transfers amount tokens of token type token_id from sender to recipient.
# @param sender : The address of the sender
# @param recipient : The address of the recipient
# @param token_id : The type of token to transfer
# @param amount : The transfer amount
@external
func safeTransferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*):
    ERC1155_safeTransferFrom(_from, to, id, amount, data_len, data)
    return ()
end

# @dev Batched version of safeTransferFrom.
# @param sender : The address of the sender
# @param recipient : The address of the recipient
# @param tokens_id_len : The length of token ids array
# @param tokens_id : The token ids array
# @param amounts_len : The length of the transfer amounts array
# @param amounts : The transfer amounts array
@external
func safeBatchTransferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*,
        data_len : felt, data : felt*):
    ERC1155_safeBatchTransferFrom(
        _from, to, ids_len, ids, amounts_len, amounts, data_len, data)
    return ()
end

# @dev Creates amount tokens of token type token_id, and assigns them to recipient.
# @dev Can only be used by owner (admin)
# @param recipient : The address of the recipient
# @param token_id : The token type
# @param amount : The amount of tokens to mint
@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*):
    Ownable_only_owner()
    _is_before_ido_launch()
    ERC1155_mint(to, id, amount, data_len, data)
    return ()
end

# @dev Batched version of _mint
# @param recipient : The address of the recipient
# @param token_ids_len : The length of the token ids array
# @param token_ids : The token ids array
# @param amounts_len : The length of the amounts array
# @param amounts : The amounts array
@external
func mintBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        to : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*,
        data_len : felt, data : felt*):
    Ownable_only_owner()
    _is_before_ido_launch()
    ERC1155_mint_batch(to, ids_len, ids, amounts_len, amounts, data_len, data)
    return ()
end

# @dev Claim Lottery tickets for one IDO
# @param token_ids_len : The length of the token ids array
# @param token_ids : The token ids array
# @param amounts_len : The length of the amounts array
# @param amounts : The amounts array
@external
func claimLotteryTickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        id : Uint256, data_len : felt, data : felt*):
    alloc_locals
    _is_before_ido_launch()

    let (caller) = get_caller_address()

    let (claimed) = has_claimed.read(caller)
    with_attr error_message("ZkPadLotteryToken::Tickets already claimed"):
        assert claimed = FALSE
    end

    # Get number of tickets to be claimed
    let (xzkp_address) = xzkp_contract_address.read()
    let (xzkp_balance: Uint256) = IERC20.balanceOf(xzkp_address, caller)
    let (amount_to_claim: Uint256) = _balance_to_tickets(xzkp_balance)

    let (has_tickets) = uint256_le(amount_to_claim, Uint256(0, 0))   
    with_attr error_message("ZkPadLotteryToken::No tickets to claim"):
        assert_not_zero(1 - has_tickets)
    end

    # Mint the tickets to the caller
    ERC1155_mint(caller, id, amount_to_claim, data_len, data)

    has_claimed.write(caller, TRUE)

    return ()
end

# @dev Destroys amount tokens of token type token_id from account
# @param _from : The address from which the tokens will be burnt
# @param id : The id of the token to burn
# @param amount : The amount of tokens to burn
@external
func burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
         _from : felt, id : Uint256, amount : Uint256):
    alloc_locals
    owner_or_approved(owner=_from)
    ERC1155_burn(_from, id, amount)
    # Spin up VRF and update allocation accordingly
    let (theAddress) = ido_contract_address.read()
    let (success) = IZkIDOContract.claim_allocation(contract_address=theAddress, amount=amount, account=_from)
    with_attr error_message("ZkPadLotteryToken::Error while claiming the allocation"):
        assert success = TRUE
    end
    return ()
end

# @external
# func burnBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#         _from : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
#     owner_or_approved(owner=_from)
#     ERC1155_burn_batch(_from, ids_len, ids, amounts_len, amounts)
#     # Spin up VRF and update allocations accordingly
#     let (theAddress) = ido_contract_address.read()
#     let (res) = IZkIDOContract.claim_allocation(contract_address=theAddress, amount=amount, account=account)
#     with_attr error_message("ZkPadLotteryToken: Error while claiming the allocation"):
#         assert res = 1
#     end
#     return ()
# end

# @dev Sets the xZKP contract address
@external
func set_xzkp_contract_address{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(address: felt):
    Ownable_only_owner()
    xzkp_contract_address.write(address)
    return()
end

# @dev Sets the IDO launch date. Calls the IDO contract to get the date.
func _set_ido_launch_date{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    let (theAddress) = ido_contract_address.read()
    let (res) = IZkIDOContract.get_ido_launch_date(contract_address=theAddress)
    ido_launch_date.write(res)

    return()
end

# @dev Checks if the current block timestamp is before the IDO launch date.
func _is_before_ido_launch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    _set_ido_launch_date()
    let (ido_launch) = ido_launch_date.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadLotteryToken::Standby Phase is over"):
        assert_nn_le(block_timestamp, ido_launch)
    end

    return()
end

# @dev Computes the amount of lottery tickets given a xZKP balance.
@view
func _balance_to_tickets{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(balance: Uint256) -> (amount_to_claim: Uint256):
    alloc_locals
    # TODO: Exponential Formula OR tier system

    return (balance)
end
