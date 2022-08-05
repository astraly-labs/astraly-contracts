%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import get_caller_address

from verify_proof import Proof, encode_proof, verify_account_proof, verify_storage_proof, hash_eip191_message, recover_address
from openzeppelin.security.initializable import Initializable

@storage_var
func _l1_headers_store_addr() -> (res : felt):
end

 # TODO: Emit
@event
func BadgeMinted(owner : felt, l1_address : felt):
end

@external
func initialize{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    l1_headers_store_addr : felt
):
    Initializable.initialize()
    _l1_headers_store_addr.write(l1_headers_store_addr)
    return ()
end

@external
func mint{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr: HashBuiltin*,
        bitwise_ptr: BitwiseBuiltin*}(
    starknet_account : felt,
    token_balance_min : felt,
    chain_id : felt,
    block_number : felt,
    account_proof_len : felt,
    storage_proof_len : felt,
    address__len : felt,
    address_ : felt*,
    state_root__len : felt,
    state_root_ : felt*,
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

    let (local proof: Proof*) = encode_proof(
        0, # balance,
        1, # nonce,
        account_proof_len,
        storage_proof_len,
        address_,
        state_root_,
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
        storage_proof_sizes_bytes_len) 

    # Extract Ethereum account address from signed message hash and signature
    let message = proof.signature.message
    let R_x = proof.signature.R_x
    let R_y = proof.signature.R_y
    let s = proof.signature.s
    let v = proof.signature.v
    let (msg_hash) = hash_eip191_message(message)
    let (ethereum_address) = recover_address(msg_hash, R_x, R_y, s, v)

    # Verify proofs, starknet and ethereum address, and min balance (TODO: Pass state_root 
    # and storage_hash so that they too can be verified from the signed message)
    verify_storage_proof(proof, starknet_account, ethereum_address, Uint256(0,token_balance_min))
    verify_account_proof(proof)

    # Write new badge entry in map
    let token = address_[1] * 2**(86*2) + 
                address_[2] * 2**86 + 
                address_[3]
    let eth_account = ethereum_address.elements[1] * 2**(86*2) + 
                      ethereum_address.elements[2] * 2**86 + 
                      ethereum_address.elements[3]
    let state_root_lo = state_root_[2] * 2**86 + 
                        state_root_[3]
    let storage_hash_lo = storage_hash_[2] * 2**86 + 
                          storage_hash_[3]

    let (caller : felt) = get_caller_address()
    BadgeMinted.emit(caller, 0)

    return ()
end
