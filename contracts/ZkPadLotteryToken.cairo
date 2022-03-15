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
    ERC1155_transferFrom,
    ERC1155_safeTransferFrom,
    ERC1155_batchTransferFrom,
    ERC1155_safeBatchTransferFrom,
    ERC1155_mint,
    ERC1155_mintBatch,
    ERC1155_burn,
    ERC1155_burnBatch,
    ERC1155_URI,
    ERC1155_setApprovalForAll,
    ERC1155_balances,
    ERC1155_assertIsOwnerOrApproved
)

@storage_var
func idoContractAddress() -> (res : felt):
end

@storage_var
func idoLaunchDate() -> (res : felt):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt, _idoContractAddress : felt):
    assert_not_zero(owner)
    Ownable_initializer(owner)
    assert_not_zero(_idoContractAddress)
    idoContractAddress.write(_idoContractAddress)
    set_idoLaunchDate()
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
func setApprovalForAll{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        operator : felt, approved : felt):
    ERC1155_setApprovalForAll(operator, approved)

    return ()
end

@external
func safeTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, token_id : felt, amount : felt):
    ERC1155_safeTransferFrom(sender, recipient, token_id, amount)

    return ()
end

@external
func safeBatchTransferFrom{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        sender : felt, recipient : felt, tokens_id_len : felt, tokens_id : felt*,
        amounts_len : felt, amounts : felt*):
    ERC1155_safeBatchTransferFrom(sender, recipient, tokens_id_len, tokens_id, amounts_len, amounts)

    return ()
end

@external
func mint{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_id : felt, amount : felt) -> ():
    ERC1155_mint(recipient, token_id, amount)

    return ()
end

@external
func mint_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        recipient : felt, token_ids_len : felt, token_ids : felt*, amounts_len : felt,
        amounts : felt*) -> ():
    ERC1155_mintBatch(recipient, token_ids_len, token_ids, amounts_len, amounts)

    return ()
end

@external
func burn{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        account : felt, token_id : felt, amount : felt):
    ERC1155_burn(account, token_id, amount)

    return ()
end

@external
func burn_batch{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
        account : felt, token_ids_len : felt, token_ids : felt*, amounts_len : felt,
        amounts : felt*):
    ERC1155_burnBatch(account, token_ids_len, token_ids, amounts_len, amounts)

    return ()
end

func set_idoLaunchDate{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}():
    alloc_locals
    let (theAddress) = idoContractAddress.read()
    let (res) = IZkIDOContract.get_ido_launch_date(contract_address=theAddress)
    idoLaunchDate.write(res)

    return()
end

@contract_interface
namespace IZkIDOContract:
    func get_ido_launch_date() -> (res : felt):
    end
end

