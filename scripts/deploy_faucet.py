from utils import deploy_try_catch, run_tx
import os
import sys

from nile.nre import NileRuntimeEnvironment

sys.path.append(os.path.dirname(__file__))

# Dummy values, should be replaced by env variables
# os.environ["SIGNER"] = "123456"
# os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def parse_ether(value: int):
    return int(value * 1e18)


WAIT_TIME = "86400"  # 1 DAY
WITHDRAWAL_AMOUNT = str(parse_ether(100))  # 300 ZKP
FAUCET_AMOUNT = to_uint(parse_ether(20_000_000))  # 20M ZKP


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    zkp_token, _ = nre.get_deployment("zkp_token")

    # Deploy Faucet
    faucet = deploy_try_catch(nre, "AstralyFaucet", [
        signer.address, zkp_token, WITHDRAWAL_AMOUNT, "0", WAIT_TIME], "faucet")

    run_tx(signer, zkp_token, "mint", [int(faucet, 16), *FAUCET_AMOUNT])
