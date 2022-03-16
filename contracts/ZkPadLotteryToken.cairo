%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_check
from starkware.cairo.common.math import assert_nn_le, assert_not_zero
from starkware.starknet.common.syscalls import (
    get_caller_address, get_block_number, get_block_timestamp
)

from contracts.Ownable_base import Ownable_initializer, Ownable_only_owner
from contracts.utils.constants import TRUE

from contracts.token.ERC1155_struct import TokenUri

from contracts.token.ERC1155_base import (
    ERC1155_initializer,
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

@external
func setURI{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(uri_ : TokenUri):
    ERC1155_URI.write(uri_)

    return ()
end

@external
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt, token_id : felt) -> (balance : felt):
    let (_balance) = ERC1155_balanceOf(owner, token_id)

    return (_balance)
end

@external
func balanceOfBatch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        owners_len : felt, 
        owners : felt*, 
        tokens_id_len : felt, 
        tokens_id : felt*) -> (balance_len : felt, balance : felt*):
    let (_balance_len, _balance) = ERC1155_balanceOfBatch(owners_len, owners, tokens_id_len, tokens_id)

    return (_balance_len, _balance)
end

@external
func isApprovedForAll{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(account : felt, operator : felt) -> (res : felt):
    let (res) = ERC1155_isApprovedForAll(account, operator)

    return (res)
end

@external
func setApprovalForAll{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        operator : felt, approved : felt):
    ERC1155_set_approval_for_all(operator, approved)

    return ()
end

@external
func safeTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, token_id : felt, amount : felt):
    ERC1155_safe_transfer_from(sender, recipient, token_id, amount)

    return ()
end

@external
func safeBatchTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, tokens_id_len : felt, tokens_id : felt*,
        amounts_len : felt, amounts : felt*):
    ERC1155_batch_transfer_from(sender, recipient, tokens_id_len, tokens_id, amounts_len, amounts)

    return ()
end

@external
func mint{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_id : felt, amount : felt) -> ():
    is_before_ido_launch()    
    ERC1155_mint(recipient, token_id, amount)

    return ()
end

@external
func mint_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_ids_len : felt, token_ids : felt*, amounts_len : felt,
        amounts : felt*) -> ():
    is_before_ido_launch()
    ERC1155_mint_batch(recipient, token_ids_len, token_ids, amounts_len, amounts)

    return ()
end

@external
func burn{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        account : felt, token_id : felt, amount : felt):
    alloc_locals
    ERC1155_burn(account, token_id, amount)
    # Claim Allocation
    let (theAddress) = ido_contract_address.read()
    let (res) = IZkIDOContract.claim_allocation(contract_address=theAddress, amount=amount, account=account)
    with_attr error_message("ZKTOKEN: Error while claiming the allocation"):
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

func set_ido_launch_date{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    let (theAddress) = ido_contract_address.read()
    let (res) = IZkIDOContract.get_ido_launch_date(contract_address=theAddress)
    ido_launch_date.write(res)

    return()
end

func is_before_ido_launch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    let (ido_launch) = ido_launch_date.read()
    let (block_timestamp) = get_block_timestamp()
    with_attr error_message("ZkPadLotteryToken: The date is past the IDO launch"):
        assert_nn_le(block_timestamp, ido_launch)
    end

    return()
end

