import json
from math import ceil

import sympy
from web3 import Web3
from eth_account.messages import encode_defunct

from pubkey_recovery import recover


def pack_intarray(hex_input: str):
    elements = []
    if hex_input.startswith("0x"):
        hex_input = hex_input[2:]
    for j in range(0, len(hex_input) // 16 + 1):
        hex_str = hex_input[j * 16:(j + 1) * 16]
        if len(hex_str) > 0:
            elements.append(int(hex_str, 16))
    return elements


def generate_proof(address, private_key, starknet_attestation_wallet, rpc_http, storage_slot,
                   erc20_token, block_number):
    w3 = Web3(Web3.HTTPProvider(rpc_http))

    # Create storage proof for an ERC20 balance at a particular block number
    slot = storage_slot[2:].rjust(64, '0')
    key = address[2:].rjust(64, '0').lower()
    position = w3.keccak(hexstr=key + slot)

    try:
        block = json.loads(open(f'block_{block_number}_{block_number}.json'))
    except:
        block = w3.eth.get_block(block_number)
        json.dump(Web3.toJSON(block), open(f'block_{block_number}_{block_number}.json', "w"), indent=4)

    try:
        proof = json.loads(open(f'proof_{erc20_token}_{block_number}_{Web3.toHex(position)}.json'))
    except:
        proof = w3.eth.get_proof(erc20_token, [position], block_number)
        json.dump(Web3.toJSON(proof), open(f'proof_{erc20_token}_{block_number}_{Web3.toHex(position)}.json', "w"),
                  indent=4)
    balance = Web3.toInt(w3.eth.get_storage_at(erc20_token, position))
    print("Generating proof of balance", balance)

    # Sign a message demonstrating control over the storage slot
    state_root = block.stateRoot.hex()
    storage_key = proof['storageProof'][0]['key'].hex()[2:]
    msg = "000000%s%s%s00000000" % (  # Pad the message with zeros to align 64bit word size in Cairo
        starknet_attestation_wallet[2:],
        state_root[2:],
        storage_key)
    message = encode_defunct(hexstr=msg)
    signed_message = w3.eth.account.sign_message(message, private_key=private_key)
    eip191_message = b'\x19' + message.version + message.header + message.body
    P = 2 ** 256 - 4294968273
    R_x = signed_message.r
    R_y = min(sympy.ntheory.residue_ntheory.sqrt_mod(R_x ** 3 + 7, P, all_roots=True))

    # Serialize proof to disk
    proof_dict = json.loads(Web3.toJSON(proof))
    proof_dict['position'] = Web3.toHex(position)
    proof_dict['storage_key'] = proof['storageProof'][0]['key'].hex()
    proof_dict['storage_value'] = balance
    proof_dict['blockNumber'] = block.number
    proof_dict['stateRoot'] = state_root
    proof_dict['storageSlot'] = slot
    proof_dict["signature"] = {
        "message": "0x" + eip191_message.hex(),
        "messageHash": signed_message.messageHash.hex(),
        "R_x": R_x,
        "R_y": R_y,
        "s": signed_message.s,
        "v": signed_message.v,
    }
    recovered_address = recover(proof_dict)
    assert Web3.toChecksumAddress(recovered_address) == address
    return proof_dict
