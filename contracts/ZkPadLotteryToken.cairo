%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_le,
    uint256_lt,
    uint256_check,
    uint256_unsigned_div_rem,
)
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_block_number,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc
from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner, Ownable_get_owner
from openzeppelin.utils.constants import TRUE, FALSE

from contracts.erc1155.ERC1155_struct import TokenUri

from contracts.erc1155.library import (
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
    owner_or_approved,
)

from contracts.utils.Math64x61 import (
    Math64x61_fromUint256,
    Math64x61_toUint256,
    Math64x61_pow,
    Math64x61_div,
    Math64x61_fromFelt,
    Math64x61_toFelt,
    Math64x61__pow_int,
)

from contracts.utils.Uint256_felt_conv import _felt_to_uint, _uint_to_felt

from InterfaceAll import IZkPadIDOContract, IERC20, IERC4626, IZKPadIDOFactory, IAccount

from starkware.cairo.common.hash import hash2

from starkware.cairo.common.math_cmp import is_le_felt

@storage_var
func ido_factory_address() -> (res : felt):
end

@storage_var
func xzkp_contract_address() -> (res : felt):
end

@storage_var
func has_claimed(id : Uint256, user : felt) -> (res : felt):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    uri : felt, owner : felt, _ido_factory_address : felt
):
    # Initialize Admin
    assert_not_zero(owner)
    Ownable_initializer(owner)
    # Initialize ERC1155
    ERC1155_initializer(uri)
    # Setup IDO Factory Params
    assert_not_zero(_ido_factory_address)
    ido_factory_address.write(_ido_factory_address)
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
func uri{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (uri : felt):
    return ERC1155_uri()
end

# @dev Returns the amount of tokens of token type token_id owned by owner
# @param owner : The address of the owner
# @param token_id : The id of the token
@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, id : Uint256
) -> (balance : Uint256):
    return ERC1155_balanceOf(account, id)
end

# @dev Batched version of balanceOf.
# @param owners_len : The length of the owners array
# @param owners : the array of owner addresses
# @param tokens_id_len : the length of the toked ids array
# @param tokens_id : the array of token ids
@view
func balanceOfBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    accounts_len : felt, accounts : felt*, ids_len : felt, ids : Uint256*
) -> (balances_len : felt, balances : Uint256*):
    return ERC1155_balanceOfBatch(accounts_len, accounts, ids_len, ids)
end

# @dev Returns true if operator is approved to transfer account's tokens.
# @param operator : The address of the operator
# @param account : The address of the account
@view
func isApprovedForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, operator : felt
) -> (is_approved : felt):
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

# return ()
# end

# @dev Grants or revokes permission to operator to transfer the caller’s tokens, according to approved
# @param operator : The address of the opertor
# @param approved : Must be 0 (revoke) or 1 (grant)
@external
func setApprovalForAll{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    operator : felt, approved : felt
):
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
    _from : felt, to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*
):
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
    _from : felt,
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    ERC1155_safeBatchTransferFrom(_from, to, ids_len, ids, amounts_len, amounts, data_len, data)
    return ()
end

# @dev Creates amount tokens of token type token_id, and assigns them to recipient.
# @dev Can only be used by owner (admin)
# @param recipient : The address of the recipient
# @param token_id : The token type
# @param amount : The amount of tokens to mint
@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    to : felt, id : Uint256, amount : Uint256, data_len : felt, data : felt*
):
    Ownable_only_owner()
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
    to : felt,
    ids_len : felt,
    ids : Uint256*,
    amounts_len : felt,
    amounts : Uint256*,
    data_len : felt,
    data : felt*,
):
    Ownable_only_owner()
    ERC1155_mint_batch(to, ids_len, ids, amounts_len, amounts, data_len, data)
    return ()
end

# @dev Claim Lottery tickets for one IDO
# @param id : IDO id
# @param data_len : The length of the data array
# @param data : The data array
@external
func claimLotteryTickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    id : Uint256, data_len : felt, data : felt*
):
    alloc_locals
    _is_before_ido_launch(id)

    let (caller) = get_caller_address()

    let (claimed) = has_claimed.read(id, caller)
    with_attr error_message("ZkPadLotteryToken::Tickets already claimed"):
        assert claimed = FALSE
    end

    # Get number of tickets to be claimed
    let (xzkp_address) = xzkp_contract_address.read()
    let (xzkp_balance : Uint256) = IERC20.balanceOf(xzkp_address, caller)

    let (has_tickets) = uint256_le(xzkp_balance, Uint256(0, 0))
    with_attr error_message("ZkPadLotteryToken::No tickets to claim"):
        assert_not_zero(1 - has_tickets)
    end

    let (amount_to_claim : Uint256) = _balance_to_tickets(xzkp_balance)

    # Mint the tickets to the caller
    ERC1155_mint(caller, id, amount_to_claim, data_len, data)

    has_claimed.write(id, caller, TRUE)

    return ()
end

# @dev Claim Lottery tickets for multiple IDOs at once
# @param ids_len : The length of the ido ids array
# @param ids : The ido ids array
# @param amounts_len : The length of the amounts array
# @param amounts : The amounts array
# @external
# func batchClaimLotteryTickets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#         ids_len : felt, ids : Uint256*, data_len: felt, data : felt*):
#     alloc_locals
#     _is_before_ido_launch()

# let (caller) = get_caller_address()

# let (claimed) = has_claimed.read(caller)
#     with_attr error_message("ZkPadLotteryToken::Tickets already claimed"):
#         assert claimed = FALSE
#     end

# # Get number of tickets to be claimed
#     let (xzkp_address) = xzkp_contract_address.read()
#     let (xzkp_balance: Uint256) = IERC20.balanceOf(xzkp_address, caller)
#     let (amount_to_claim: Uint256) = _balance_to_tickets(xzkp_balance)

# let (has_tickets) = uint256_le(amount_to_claim, Uint256(0, 0))
#     with_attr error_message("ZkPadLotteryToken::No tickets to claim"):
#         assert_not_zero(1 - has_tickets)
#     end

# let (amounts_to_claim: Uint256*) = _to_array(amount_to_claim, ids_len)

# # Mint the tickets to the caller
#     ERC1155_mint_batch(caller, ids_len, ids, ids_len, amounts_to_claim, data_len, data)

# has_claimed.write(caller, TRUE)

# return ()
# end

# @dev Destroys amount tokens of token type token_id from account
# @param _from : The address from which the tokens will be burnt
# @param id : The id of the token to burn
# @param amount : The amount of tokens to burn
@external
func burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _from : felt, id : Uint256, amount : Uint256
):
    alloc_locals
    owner_or_approved(owner=_from)
    ERC1155_burn(_from, id, amount)
    # Spin up VRF and update allocation accordingly
    let (factory_address : felt) = ido_factory_address.read()
    let (felt_id : felt) = _uint_to_felt(id)
    let (ido_address : felt) = IZKPadIDOFactory.get_ido_address(
        contract_address=factory_address, id=felt_id
    )
    let (success : felt) = IZkPadIDOContract.register_user(
        contract_address=ido_address, amount=amount, account=_from, nb_quest=0
    )
    with_attr error_message("ZkPadLotteryToken::Error while claiming the allocation"):
        assert success = TRUE
    end
    return ()
end

@external
func burn_with_quest{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _from : felt,
    id : Uint256,
    amount : Uint256,
    nb_quest : felt,
    merkle_proof_len : felt,
    merkle_proof : felt*,
):
    alloc_locals
    owner_or_approved(owner=_from)
    let (factory_address : felt) = ido_factory_address.read()
    let (leaf) = hash2{hash_ptr=pedersen_ptr}(_from, nb_quest)
    let (_id : felt) = _uint_to_felt(id)
    let (merkle_root : felt) = IZKPadIDOFactory.get_merkle_root(
        contract_address=factory_address, id=_id
    )
    local root_loc = merkle_root
    let (_valid : felt) = merkle_verify(leaf, merkle_root, merkle_proof_len, merkle_proof)
    with_attr error_message("ZkPadLotteryToken::Error in the number of quests done"):
        assert _valid = 1
    end
    ERC1155_burn(_from, id, amount)
    # Spin up VRF and update allocation accordingly
    let (ido_address : felt) = IZKPadIDOFactory.get_ido_address(
        contract_address=factory_address, id=_id
    )
    let (success : felt) = IZkPadIDOContract.register_user(
        contract_address=ido_address, amount=amount, account=_from, nb_quest=nb_quest
    )
    with_attr error_message("ZkPadLotteryToken::Error while claiming the allocation"):
        assert success = TRUE
    end
    return ()
end

func merkle_verify{pedersen_ptr : HashBuiltin*, range_check_ptr}(
    leaf : felt, root : felt, proof_len : felt, proof : felt*
) -> (res : felt):
    let (calc_root) = calc_merkle_root(leaf, proof_len, proof)
    # check if calculated root is equal to expected
    if calc_root == root:
        return (1)
    else:
        return (0)
    end
end

func calc_merkle_root{pedersen_ptr : HashBuiltin*, range_check_ptr}(
    curr : felt, proof_len : felt, proof : felt*
) -> (res : felt):
    alloc_locals

    if proof_len == 0:
        return (curr)
    end

    local node
    local proof_elem = [proof]
    let (le) = is_le_felt(curr, proof_elem)

    if le == 1:
        let (n) = hash2{hash_ptr=pedersen_ptr}(curr, proof_elem)
        node = n
    else:
        let (n) = hash2{hash_ptr=pedersen_ptr}(proof_elem, curr)
        node = n
    end

    let (res) = calc_merkle_root(node, proof_len - 1, proof + 1)
    return (res)
end
# @external
# func burnBatch{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
#         _from : felt, ids_len : felt, ids : Uint256*, amounts_len : felt, amounts : Uint256*):
#     owner_or_approved(owner=_from)
#     ERC1155_burn_batch(_from, ids_len, ids, amounts_len, amounts)
#     # Spin up VRF and update allocations accordingly
#     let (theAddress) = ido_contract_address.read()
#     let (res) = IZkIDOContract.register_user(contract_address=theAddress, amount=amount, account=account)
#     with_attr error_message("ZkPadLotteryToken: Error while claiming the allocation"):
#         assert res = 1
#     end
#     return ()
# end

# @dev Sets the xZKP contract address
@external
func set_xzkp_contract_address{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    address : felt
):
    Ownable_only_owner()
    xzkp_contract_address.write(address)
    return ()
end

# @dev Sets the IDO Factory address
@external
func set_ido_factory_address{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    address : felt
):
    Ownable_only_owner()
    ido_factory_address.write(address)
    return ()
end

# @dev Checks if the current block timestamp is before the IDO launch date.
func _is_before_ido_launch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    id : Uint256
):
    alloc_locals
    let (factory_address : felt) = ido_factory_address.read()
    let (felt_id : felt) = _uint_to_felt(id)
    let (ido_launch) = IZKPadIDOFactory.get_ido_launch_date(
        contract_address=factory_address, id=felt_id
    )
    let (block_timestamp) = get_block_timestamp()

    with_attr error_message("ZkPadLotteryToken::Standby Phase is over"):
        assert_nn_le(block_timestamp, ido_launch)
    end

    return ()
end

# @dev Constructs an array with a number given a certain length
# func _to_array{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(number: Uint256, length: felt) -> (array: Uint256*):
#     alloc_locals
#     uint256_check(number)
#     assert_not_zero(length)

# let (new_array: felt*) = alloc()

# return (new_array)
# end

# @dev Computes the amount of lottery tickets given a xZKP balance : N = x^(3/5)
@view
func _balance_to_tickets{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    balance : Uint256
) -> (amount_to_claim : Uint256):
    alloc_locals
    let one_unit : Uint256 = Uint256(10 ** 18, 0)
    let (fixed_balance : Uint256, _) = uint256_unsigned_div_rem(balance, one_unit)
    let (adjusted_bal) = Math64x61_fromUint256(fixed_balance)

    let (fixed3) = Math64x61_fromFelt(3)
    let (fixed5) = Math64x61_fromFelt(5)
    let (power) = Math64x61_div(fixed3, fixed5)
    let (fixed_nb_tickets) = Math64x61_pow(adjusted_bal, power)
    let (scaled_nb_tickets) = Math64x61_toFelt(fixed_nb_tickets)
    let (nb_tickets : Uint256) = _felt_to_uint(scaled_nb_tickets)

    return (nb_tickets)
end

@view
func checkKYCSignature{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*
}(sig_len : felt, sig : felt*):
    alloc_locals
    let (caller) = get_caller_address()
    let (admin_address) = Ownable_get_owner()

    let (user_hash) = hash2{hash_ptr=pedersen_ptr}(caller, 0)

    # Verify the user's signature.
    IAccount.is_valid_signature(admin_address, user_hash, sig_len, sig)

    return ()
end
