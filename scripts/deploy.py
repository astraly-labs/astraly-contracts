
import os

# Dummy values, should be replaced by env variables
os.environ["SIGNER"] = "123456"
os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


INITIAL_SUPPLY = "10000000000000000000000"
MAX_SUPPLY = "10000000000000000000000"
DECIMALS = "18"
NAME = str_to_felt("ZkPad")
SYMBOL = str_to_felt("ZKP")

XZKP_NAME = str_to_felt("ZkPad")
XZKP_SYMBOL = str_to_felt("ZKP")


def run(nre):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    # Deploy ZKP token
    try:
        zkp_token, abi = nre.deploy("ZkPadToken", arguments=[
            str(NAME),
            str(SYMBOL),
            DECIMALS,
            INITIAL_SUPPLY,
            "0",
            user_1.address,
            signer.address,
            MAX_SUPPLY,
            "0",
            user_1.address  # distribution address
        ], alias="zkp_token")
    except Exception as error:
        if "already exists" in str(error):
            zkp_token, abi = nre.get_deployment("zkp_token")
        else:
            print(f"DEPLOYMENT ERROR: {error}")

    print(f"Deployed ZKP token to {zkp_token}")

    try:
        xzkp_token, abi = nre.deploy(
            "ZkPadStaking",
            arguments=[str(XZKP_NAME), str(XZKP_SYMBOL), zkp_token],
            alias="xzkp_token")
    except Exception as error:
        if "already exists" in str(error):
            xzkp_token, abi = nre.get_deployment("xzkp_token")
        else:
            print(f"DEPLOYMENT ERROR: {error}")

    print(f"Deployed xZKP token to {xzkp_token}")
