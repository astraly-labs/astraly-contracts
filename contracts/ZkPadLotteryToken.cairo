%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_check
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address, get_block_number, get_block_timestamp
)

from contracts.openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner
from contracts.openzeppelin.utils.constants import TRUE

from contracts.token.ERC1155_struct import TokenUri

from contracts.token.ERC1155_base import (
    ERC1155_initializer,
    ERC1155_get_URI,
    ERC1155_transfer_from,
    ERC1155_safe_transfer_from,
    ERC1155_batch_transfer_from,
    ERC1155_safe_batch_transfer_from,
    ERC1155_mint,
    ERC1155_mint_batch,
    ERC1155_burn,
    ERC1155_burn_batch,
    ERC1155_URI,
    ERC1155_set_approval_for_all,
    ERC1155_balanceOf,
    ERC1155_balanceOfBatch,
    ERC1155_isApprovedForAll
)

from InterfaceAll import (IZkIDOContract)

@storage_var
func ido_contract_address() -> (res : felt):
end

@storage_var
func ido_launch_date() -> (res : felt):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt, _ido_contract_address : felt):
    assert_not_zero(owner)
    Ownable_initializer(owner)
    assert_not_zero(_ido_contract_address)
    ido_contract_address.write(_ido_contract_address)
    set_ido_launch_date()
    return ()
end

#
# Externals
#

# @dev Returns the URI for all token types
@external
func getURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : TokenUri):
    let (res) = ERC1155_get_URI()

    return (res)
end

# @dev Sets the URI for all token types
# @param uri_ : The TokenUri to use . See the ERC1155_struct for more details about the TokenUri type.
@external
func setURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(uri_ : TokenUri):
    ERC1155_URI.write(uri_)

    return ()
end

# @dev Returns the amount of tokens of token type token_id owned by owner
# @param owner : The address of the owner
# @param token_id : The id of the token
@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt, token_id : felt) -> (balance : felt):
    let (_balance) = ERC1155_balanceOf(owner, token_id)

    return (_balance)
end

# @dev Batched version of balanceOf.
# @param owners_len : The length of the owners array
# @param owners : the array of owner addresses
# @param tokens_id_len : the length of the toked ids array
# @param tokens_id : the array of token ids
@view
func balanceOfBatch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        owners_len : felt, 
        owners : felt*, 
        tokens_id_len : felt, 
        tokens_id : felt*) -> (balance_len : felt, balance : felt*):
    let (_balance_len, _balance) = ERC1155_balanceOfBatch(owners_len, owners, tokens_id_len, tokens_id)

    return (_balance_len, _balance)
end

# @dev Returns true if operator is approved to transfer account's tokens.
# @param operator : The address of the operator
# @param account : The address of the account
@view
func isApprovedForAll{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(account : felt, operator : felt) -> (res : felt):
    let (res) = ERC1155_isApprovedForAll(account, operator)

    return (res)
end

# @dev Grants or revokes permission to operator to transfer the caller’s tokens, according to approved
# @param operator : The address of the opertor
# @param approved : Must be 0 (revoke) or 1 (grant)
@external
func setApprovalForAll{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        operator : felt, approved : felt):
    ERC1155_set_approval_for_all(operator, approved)

    return ()
end

# @dev Transfers amount tokens of token type token_id from sender to recipient.
# @param sender : The address of the sender
# @param recipient : The address of the recipient
# @param token_id : The type of token to transfer
# @param amount : The transfer amount
@external
func safeTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, token_id : felt, amount : felt):
    ERC1155_safe_transfer_from(sender, recipient, token_id, amount)

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
func safeBatchTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, tokens_id_len : felt, tokens_id : felt*,
        amounts_len : felt, amounts : felt*):
    ERC1155_batch_transfer_from(sender, recipient, tokens_id_len, tokens_id, amounts_len, amounts)

    return ()
end

# @dev Creates amount tokens of token type token_id, and assigns them to recipient.
# @param recipient : The address of the recipient
# @param token_id : The token type
# @param amount : The amount of tokens to mint
@external
func mint{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_id : felt, amount : felt) -> ():
    is_before_ido_launch()    
    ERC1155_mint(recipient, token_id, amount)

    return ()
end

# @dev Batched version of _mint
# @param recipient : The address of the recipient
# @param token_ids_len : The length of the token ids array
# @param token_ids : The token ids array
# @param amounts_len : The legth of the amounts array
# @param amounts : The amounts array
@external
func mint_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_ids_len : felt, token_ids : felt*, amounts_len : felt,
        amounts : felt*) -> ():
    is_before_ido_launch()
    ERC1155_mint_batch(recipient, token_ids_len, token_ids, amounts_len, amounts)

    return ()
end

# @dev Destroys amount tokens of token type token_id from account
# @param account : The address from which the tokens will be burnt
# @param token_id : The type of the token to brun
# @param amount : The amount of tokens to burn
@external
func burn{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        account : felt, token_id : felt, amount : felt):
    alloc_locals
    ERC1155_burn(account, token_id, amount)
    # Claim Allocation
    let (theAddress) = ido_contract_address.read()
    let (res) = IZkIDOContract.claim_allocation(contract_address=theAddress, amount=amount, account=account)
    with_attr error_message("ZkPadLotteryToken: Error while claiming the allocation"):
        assert res = 1
    end
    return ()
end

# @external
# func burn_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
#         account : felt, token_ids_len : felt, token_ids : felt*, amounts_len : felt,
#         amounts : felt*):
#     alloc_locals
#     ERC1155_burn_batch(account, token_ids_len, token_ids, amounts_len, amounts)
#     # Claim Allocation
#     let (theAddress) = ido_contract_address.read()
#     let (res) = IZkIDOContract.claim_allocation(contract_address=theAddress, amount=amount, account=account)
#     with_attr error_message("ZKTOKEN: Error while claiming the allocation"):
#         assert res = 1
#     end
#     return ()
# end

# @dev Sets the IDO launch date. Calls the IDO contract to get the date.
func set_ido_launch_date{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    let (theAddress) = ido_contract_address.read()
    let (res) = IZkIDOContract.get_ido_launch_date(contract_address=theAddress)
    ido_launch_date.write(res)

    return()
end

# @dev Checks if the current block timestamp is before the IDO launch date.
func is_before_ido_launch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    let (ido_launch) = ido_launch_date.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadLotteryToken: Lottery Ticket Expired"):
        assert_nn_le(block_timestamp, ido_launch)
    end

    return()
end
