import os

from nile.nre import NileRuntimeEnvironment

# Dummy values, should be replaced by env variables
os.environ["SIGNER"] = "123456"
os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


WAIT_TIME = "3600"
WITHDRAWAL_AMOUNT = "100000000000000000000"


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    zkp_token, _ = nre.get_deployment("zkp_token")

    # Deploy Faucet
    faucet = None
    try:
        faucet, _ = nre.deploy("ZkPadFaucet", arguments=[
                               signer.address, zkp_token, WITHDRAWAL_AMOUNT, "0", WAIT_TIME], alias="faucet")
    except Exception as error:
        if "already exists" in str(error):
            faucet, _ = nre.get_deployment("faucet")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Faucet deployed at {faucet}")

    tx = signer.send(zkp_token, "mint",
                     [int(faucet, 16), *to_uint(100000000000000000000000)])
    print(tx)
