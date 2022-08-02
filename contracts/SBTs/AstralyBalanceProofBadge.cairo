%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.cairo_secp.signature import verify_eth_signature
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.math import assert_not_zero
# from starkware.cairo.common.keccak import keccak_felts
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_caller_address

from openzeppelin.security.initializable import Initializable
from starknet.types import Keccak256Hash, IntsSequence
from starknet.lib.blockheader_rlp_extractor import decode_state_root

from contracts.SBTs.IL1HeadersStore import IL1HeadersStore

@storage_var
func _l1_headers_store_addr() -> (res : felt):
end

@event
func BadgeMinted(receiver : felt, l1_address : felt):
end

@view
func get_l1_headers_store_addr{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    ) -> (res : felt):
    return _l1_headers_store_addr.read()
end

@external
func initialize{pedersen_ptr : HashBuiltin*, syscall_ptr : felt*, range_check_ptr}(
    l1_headers_store_addr : felt
):
    Initializable.initialize()
    _l1_headers_store_addr.write(l1_headers_store_addr)
    return ()
end

@external
func mint{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(
    block_number : felt,
    msg_hash : BigInt3,
    r : BigInt3,
    s : BigInt3,
    v : felt,
    eth_address : felt,
    block_header_rlp_bytes_len : felt,
    block_header_rlp_len : felt,
    block_header_rlp : felt*,
):
    alloc_locals
    # TODO: check if the signed message is the user SN address
    # let (caller) = get_caller_address()
    # verify_eth_signature(msg_hash, r, s, v, eth_address)

    # let (array : felt*) = alloc()
    # assert array[0] = caller
    # # let (keccak_output : Uint256) = keccak_felts(1, array)

    # with_attr error_message("Signature doesn't contain the hash of the caller"):
    #     assert keccak_output.low = msg_hash
    # end

    with_attr error_message("Invalid block"):
        assert_not_zero(block_number)
    end

    let (l1_headers_store_address : felt) = _l1_headers_store_addr.read()
    with_attr error_message("Fossil L1HeadersStore contract address not set"):
        assert_not_zero(l1_headers_store_address)
    end
    let (state_root_hash : Keccak256Hash) = IL1HeadersStore.get_state_root(
        l1_headers_store_address, block_number
    )

    tempvar block_rlp : IntsSequence = IntsSequence(block_header_rlp, block_header_rlp_len, block_header_rlp_bytes_len)

    let (provided_state_root_hash : Keccak256Hash) = decode_state_root(block_rlp)
    with_attr error_message("Invalid block_rlp provided for the block block number {block_number}"):
        assert state_root_hash.word_1 = provided_state_root_hash.word_1
        assert state_root_hash.word_2 = provided_state_root_hash.word_2
        assert state_root_hash.word_3 = provided_state_root_hash.word_3
        assert state_root_hash.word_4 = provided_state_root_hash.word_4
    end

    return ()
end
