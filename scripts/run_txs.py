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


# Dummy values, should be replaced by env variables
# os.environ["SIGNER"] = "123456"
# os.environ["USER_1"] = "12345654321"

# os.environ["ADMIN_1"] = "23456765432"
# os.environ["ADMIN_2"] = "34567876543"
# os.environ["NUMBER_OF_ADMINS"] = "2"
# os.environ["XOROSHIRO_RNG_SEED"] = "984375843"

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

    run_tx(signer, lottery_token,
           "set_xzkp_contract_address", [int(xzkp_token, 16)])

    run_tx(signer, lottery_token, "set_ido_factory_address",
           [int(factory_contract, 16)])

    # set IDO Factory contract variables
    # tx3 = signer.send(factory_contract, "set_task_address",
    #                   [int(task_contract, 16)]
    #                   )
    # print(tx3)

    # tx4 = signer.send(factory_contract, "create_ido",
    #                   [int(ido_contract_full, 16)]
    #                   )
    # print(tx4)

    # tx5 = signer.send(factory_contract, "set_lottery_ticket_contract_address",
    #                   [int(lottery_token, 16)]
    #                   )
    # print(tx5)

    # # set IDO contract sale parameters
    # tx6 = admin_1.send(ido_contract_full, "set_sale_params",
    #                    [
    #                        # _token_address : felt
    #                        int(zkp_token, 16),
    #                        # _sale_owner_address : felt
    #                        int(signer.address, 16),
    #                        # _token_price : Uint256
    #                        *to_uint(int(IDO_TOKEN_PRICE)),
    #                        # _amount_of_tokens_to_sell : Uint256
    #                        *to_uint(int(IDO_TOKENS_TO_SELL)),
    #                        # _sale_end_time : felt
    #                        int(IDO_SALE_END.timestamp()),
    #                        # _tokens_unlock_time : felt
    #                        int(IDO_TOKEN_UNLOCK.timestamp()),
    #                        # _portion_vesting_precision : Uint256
    #                        *to_uint(int(IDO_PORTION_VESTING_PRECISION)),
    #                        # _lottery_tickets_burn_cap : Uint256
    #                        *to_uint(int(IDO_LOTTERY_TOKENS_BURN_CAP))
    #                    ]
    #                    )
    # print(tx6)
    # print("IDO Sale Params Set...")

    # # set IDO vesting parameters
    # tx7 = admin_1.send(ido_contract_full, "set_vesting_params",
    #                    [
    #                        4,
    #                        *VESTING_TIMES_UNLOCKED,
    #                        *uarr2cd(VESTING_PERCENTAGES),
    #                        0
    #                    ]
    #                    )
    # print(tx7)

    # tx8 = admin_1.send(ido_contract_full, "set_registration_time", [
    #                    int(REGISTRATION_START.timestamp()), int(REGISTRATION_END.timestamp())])
    # print(tx8)

    # print("IDO Vesting Params Set...")

    print("Done...")
