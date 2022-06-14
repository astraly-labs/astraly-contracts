import os

from nile.nre import NileRuntimeEnvironment
from nile.core.account import Signer

# Dummy values, should be replaced by env variables
os.environ["SIGNER"] = "123456"
os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def run(nre: NileRuntimeEnvironment):
    signer = Signer("")
    print(signer.public_key)
