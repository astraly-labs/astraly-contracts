%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, split_64
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.math import assert_not_zero, split_felt
from starkware.starknet.common.syscalls import get_caller_address, get_tx_info, TxInfo
from starkware.starknet.common.eth_utils import assert_valid_eth_address

from lib.secp.bigint import BigInt3
from lib.bytes_utils import IntArray
from fossil.contracts.starknet.FactsRegistry import IL1HeadersStore, Keccak256Hash
from verify_proof import (
    Proof,
    encode_proof,
    verify_storage_proof,
    verify_account_proof,
    hash_eip191_message,
    recover_address,
)
from openzeppelin.token.erc721.library import ERC721

from contracts.SBT.AstralyBalanceSBTContractFactory import IAstralySBTContractFactory
from contracts.SBT.base_SBT import name, symbol, balanceOf, ownerOf, unequip

@storage_var
func block_number() -> (res : felt):
end

@storage_var
func min_balance() -> (res : felt):
end

@storage_var
func token_address() -> (res : felt):
end

@storage_var
func proofs(msg_hash : BigInt3) -> (minted : felt):
end

@storage_var
func _state_root() -> (keccak : Keccak256Hash):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _block_number : felt,
    _balance : felt,
    _token_address : felt,
    _fossil_fact_registry_address : felt,
):
    let (fossil_stored_state_root : Keccak256Hash) = IL1HeadersStore.get_state_root(
        _fossil_fact_registry_address, _block_number
    )

    with_attr error_message("No state root hash available for this block number"):
        tempvar sum = fossil_stored_state_root.word_1 +
            fossil_stored_state_root.word_2 +
            fossil_stored_state_root.word_3 +
            fossil_stored_state_root.word_4
        assert_not_zero(sum)
    end

    block_number.write(_block_number)
    min_balance.write(_balance)
    assert_valid_eth_address(_token_address)
    token_address.write(_token_address)

    ERC721.initializer('AstralyBalanceProofBadge', 'A-BPB')
    return ()
end

@view
func minBalance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    min : felt
):
    let (_min_balance : felt) = min_balance.read()
    return (_min_balance)
end

@view
func tokenAddress{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (address : felt) = token_address.read()
    return (address)
end

@view
func blockNumber{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    block : felt
):
    let (block_no : felt) = block_number.read()
    return (block_no)
end

@external
func mint{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, bitwise_ptr : BitwiseBuiltin*
}(
    starknet_account : felt,
    token_balance : felt,
    token_contract_nonce : felt,
    account_proof_len : felt,
    storage_proof_len : felt,
    code_hash__len : felt,
    code_hash_ : felt*,
    storage_slot__len : felt,
    storage_slot_ : felt*,
    storage_hash__len : felt,
    storage_hash_ : felt*,
    message__len : felt,
    message_ : felt*,
    message_byte_len : felt,
    R_x__len : felt,
    R_x_ : felt*,
    R_y__len : felt,
    R_y_ : felt*,
    s__len : felt,
    s_ : felt*,
    v : felt,
    storage_key__len : felt,
    storage_key_ : felt*,
    storage_value__len : felt,
    storage_value_ : felt*,
    account_proofs_concat_len : felt,
    account_proofs_concat : felt*,
    account_proof_sizes_words_len : felt,
    account_proof_sizes_words : felt*,
    account_proof_sizes_bytes_len : felt,
    account_proof_sizes_bytes : felt*,
    storage_proofs_concat_len : felt,
    storage_proofs_concat : felt*,
    storage_proof_sizes_words_len : felt,
    storage_proof_sizes_words : felt*,
    storage_proof_sizes_bytes_len : felt,
    storage_proof_sizes_bytes : felt*,
):
    alloc_locals

    # TODO: check block number and state root on fossil
    let (_block_number : felt) = blockNumber()

    let (state_root : Keccak256Hash) = _state_root.read()
    let state_root_arr : felt* = alloc()
    assert state_root_arr[0] = state_root.word_1
    assert state_root_arr[1] = state_root.word_2
    assert state_root_arr[2] = state_root.word_3
    assert state_root_arr[3] = state_root.word_4

    let (_token_address : felt) = tokenAddress()
    let (address : felt*) = felt_to_int_array(_token_address)

    let (local proof : Proof*) = encode_proof(
        token_balance,
        token_contract_nonce,
        account_proof_len,
        storage_proof_len,
        address,
        state_root_arr,
        code_hash_,
        storage_slot_,
        storage_hash_,
        message_,
        message__len,
        message_byte_len,
        R_x_,
        R_y_,
        s_,
        v,
        storage_key_,
        storage_value_,
        account_proofs_concat,
        account_proofs_concat_len,
        account_proof_sizes_words,
        account_proof_sizes_words_len,
        account_proof_sizes_bytes,
        account_proof_sizes_bytes_len,
        storage_proofs_concat,
        storage_proofs_concat_len,
        storage_proof_sizes_words,
        storage_proof_sizes_words_len,
        storage_proof_sizes_bytes,
        storage_proof_sizes_bytes_len,
    )

    # Extract Ethereum account address from signed message hash and signature
    let message = proof.signature.message
    let R_x = proof.signature.R_x
    let R_y = proof.signature.R_y
    let s = proof.signature.s
    let v = proof.signature.v
    let (msg_hash : BigInt3) = hash_eip191_message(message)
    assert_uniq_hash_msg(msg_hash)
    let (ethereum_address : IntArray) = recover_address(msg_hash, R_x, R_y, s, v)

    let (_min_balance : felt) = min_balance.read()

    # Verify proofs, starknet and ethereum address, and min balance (TODO: Pass state_root
    # and storage_hash so that they too can be verified from the signed message)
    verify_storage_proof(proof, starknet_account, ethereum_address, Uint256(_min_balance, 0))
    # verify_account_proof(proof)

    # Write new badge entry in map
    let (eth_account) = int_array_to_felt(ethereum_address.elements, 4)
    assert_valid_eth_address(eth_account)

    let (caller : felt) = get_caller_address()

    ERC721._mint(
        caller, Uint256(storage_key_[0] + storage_key_[1], storage_key_[2] + storage_key_[3])
    )
    return ()
end

func assert_uniq_hash_msg{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    msg_hash : BigInt3
):
    let (minted : felt) = proofs.read(msg_hash)
    assert minted = FALSE

    return ()
end

func int_array_to_felt(a : felt*, word_len : felt) -> (res : felt):
    if word_len == 1:
        return (a[0])
    end
    if word_len == 2:
        return (a[1] + a[0] * 2 ** 64)
    end
    if word_len == 3:
        return (a[2] + a[1] * 2 ** 64 + a[0] * 2 ** 128)
    end
    if word_len == 4:
        return (a[3] + a[2] * 2 ** 64 + a[1] * 2 ** 128 + a[0] * 2 ** 192)
    end
    return (0)
end

func felt_to_int_array{range_check_ptr}(a : felt) -> (res : felt*):
    alloc_locals
    let (hi, lo) = split_felt(a)
    let (local res : felt*) = alloc()
    let (r0, r1) = split_64(lo)
    let (r2, r3) = split_64(hi)
    assert res[0] = r3
    assert res[1] = r2
    assert res[2] = r1
    assert res[3] = r0
    return (res)
end
