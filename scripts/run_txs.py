import os
import sys
import subprocess
import re
from datetime import datetime, timedelta
import time

from nile.nre import NileRuntimeEnvironment

sys.path.append(os.path.dirname(__file__))
from utils import run_tx



def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def uint_array(l):
    return list(map(to_uint, l))


def uarr2cd(arr):
    acc = [len(arr)]
    for lo, hi in arr:
        acc.append(lo)
        acc.append(hi)
    return acc


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def parse_ether(value: int):
    return int(value * 1e18)


XZKP_NAME = str_to_felt("xZkPad")
XZKP_SYMBOL = str_to_felt("xZKP")

REWARDS_PER_BLOCK = to_uint(parse_ether(10))
START_BLOCK = 0
END_BLOCK = START_BLOCK + 10000

IDO_TOKEN_PRICE = "10000000000000000"  # 0.01 ETH
IDO_TOKENS_TO_SELL = "100000000000000000000000"  # 100,000 TOKENS
# vestion portion percentages must add up to 1000
IDO_PORTION_VESTING_PRECISION = "1000"
# users can't burn more than 10000 lottery tickets
IDO_LOTTERY_TOKENS_BURN_CAP = "10000"

day = datetime.today()
timeDeltadays = timedelta(days=30)
timeDeltaWeeks = timedelta(weeks=1)
IDO_SALE_END = day + timeDeltadays
REGISTRATION_END = day + timedelta(days=2)
REGISTRATION_START = day + timedelta(days=1)
IDO_TOKEN_UNLOCK = IDO_SALE_END + timeDeltaWeeks

# VESTING_PERCENTAGES & VESTING_TIMES_UNLOCKED arrays must match in length
VESTING_PERCENTAGES = uint_array([100, 200, 300, 400])
VESTING_TIMES_UNLOCKED = [
    int(IDO_TOKEN_UNLOCK.timestamp()) + (1 * 24 *
                                         60 * 60),  # 1 day after tokens unlock time
    # 8 days after tokens unlock time
    int(IDO_TOKEN_UNLOCK.timestamp()) + (8 * 24 * 60 * 60),
    # 15 days after tokens unlock time
    int(IDO_TOKEN_UNLOCK.timestamp()) + (15 * 24 * 60 * 60),
    # 22 days after tokens unlock time
    int(IDO_TOKEN_UNLOCK.timestamp()) + (22 * 24 * 60 * 60)
]


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    admin_1 = nre.get_or_deploy_account("ADMIN_1")
    admin_2 = nre.get_or_deploy_account("ADMIN_2")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")
    print(f"Admin1 account: {admin_1.address}")
    print(f"Admin2 account: {admin_2.address}")

    xzkp_token, _ = nre.get_deployment("xzkp_token_proxy")
    zkp_token, zkp_token_abi = nre.get_deployment("zkp_token")
    admin_contract, admin_contract_abi = nre.get_deployment("admin_contract")
    zkp_token, zkp_token_abi = nre.get_deployment("zkp_token")
    xoroshiro_contract, xoroshiro_contract_abi = nre.get_deployment(
        "xoroshiro_contract")
    factory_contract, factory_contract_abi = nre.get_deployment(
        "factory_contract")
    lottery_token, lottery_token_abi = nre.get_deployment("lottery_token")
    zkp_token, zkp_token_abi = nre.get_deployment("zkp_token")
    task_contract, task_contract_abi = nre.get_deployment("task_contract")
    ido_contract_full, ido_contract_full_abi = nre.get_deployment(
        "ido_contract_full")

    # Initialize Lottery Token Params

    run_tx(signer, lottery_token,
           "set_xzkp_contract_address", [int(xzkp_token, 16)])

    run_tx(signer, lottery_token, "set_ido_factory_address",
           [int(factory_contract, 16)])

    # Initialize Proxy

    run_tx(signer, xzkp_token, "initializer", [
        str(XZKP_NAME),
        str(XZKP_SYMBOL),
        int(zkp_token, 16),
        int(signer.address, 16),
        *REWARDS_PER_BLOCK,
        START_BLOCK,
        END_BLOCK
    ])

    # Initialize Factory

    run_tx(signer, factory_contract,
           "set_lottery_ticket_contract_address", [int(lottery_token, 16)])

    print("CONTRACTS SUCCESSFULLY INITIALIZED 🚀")
