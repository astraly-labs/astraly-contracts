import os

from nile.nre import NileRuntimeEnvironment

# Dummy values, should be replaced by env variables
os.environ["SIGNER"]  = "123456"
os.environ["USER_1"]  = "12345654321"
os.environ["ADMIN_1"] = "23456765432"
os.environ["ADMIN_2"] = "34567876543"

def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")

def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    admin_1 = nre.get_or_deploy_account("ADMIN_1")
    admin_2 = nre.get_or_deploy_account("ADMIN_2")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")
    print(f"Admin1 account: {admin_1.address}")
    print(f"Admin2 account: {admin_2.address}")

