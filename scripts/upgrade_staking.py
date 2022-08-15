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


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    xzkp_token, _ = nre.get_deployment("xzkp_token_proxy")

    xzkp_token_implementation = None
    try:
        xzkp_token_implementation, abi = nre.deploy(
            "AstralyStaking", alias="xzkp_token_implementation")
    except Exception as error:
        if "already exists" in str(error):
            xzkp_token_implementation, _ = nre.get_deployment(
                "xzkp_token_implementation")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(
            f"xZKP token implementation deployed to {xzkp_token_implementation}")

    signer.send(xzkp_token, 'upgrade', [int(xzkp_token_implementation, 16)])
