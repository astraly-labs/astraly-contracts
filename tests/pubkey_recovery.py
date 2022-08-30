import json

from web3 import Web3

from eth_keys import keys
from eth_keys.backends.native.ecdsa import ecdsa_raw_recover


def recover(proof):
    # Extract ecrecover arguments
    hex_message_hash = proof['signature']['messageHash']
    bytes_message_hash = Web3.toBytes(hexstr=hex_message_hash)
    r = proof['signature']['R_x']
    s = proof['signature']['s']
    v = proof['signature']['v']
    canonical_v = v - 27
    vrs = (canonical_v, r, s)

    # Recover public key using eth_keys API
    signature = keys.Signature(vrs=vrs)
    public_key = signature.recover_public_key_from_msg_hash(bytes_message_hash)
    print(public_key.to_hex())

    # Recover public key using Jacobian projection
    raw_public_key_bytes = ecdsa_raw_recover(Web3.toBytes(bytes_message_hash), vrs)
    print(Web3.toHex(raw_public_key_bytes))

    # Print canonical Ethereum address
    address = public_key.to_canonical_address()
    return Web3.toHex(address)
