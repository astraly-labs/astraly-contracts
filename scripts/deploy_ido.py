import os
import sys
from datetime import datetime, timedelta

from nile.nre import NileRuntimeEnvironment

sys.path.append(os.path.dirname(__file__))
from utils import deploy_try_catch, run_tx


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

    admin_contract, admin_contract_abi = nre.get_deployment("admin_contract")
    xoroshiro_contract, xoroshiro_contract_abi = nre.get_deployment(
        "xoroshiro_contract")
    factory_contract, factory_contract_abi = nre.get_deployment(
        "factory_contract")
    lottery_token, lottery_token_abi = nre.get_deployment("lottery_token")
    zkp_token, zkp_token_abi = nre.get_deployment("zkp_token")

    # deploy Task contract
    task_contract = deploy_try_catch(nre, "ZkPadTask", [
        factory_contract
    ], f"task_contract_{day}")

    # deploy IDO contract
    ido_contract_full = deploy_try_catch(nre, "ZkPadIDOContract", [
        admin_contract,
        factory_contract
    ], f"ido_contract_{day}")

    # Set Task Address
    run_tx(signer, factory_contract,
           "set_task_address", [int(task_contract, 16)])

    # Create IDO
    run_tx(signer, factory_contract, "create_ido",
           [])

    # set IDO contract sale parameters
    run_tx(admin_1, ido_contract_full, "set_sale_params", [
        # _token_address : felt
        int(zkp_token, 16),
        # _sale_owner_address : felt
        int(signer.address, 16),
        # _token_price : Uint256
        *to_uint(int(IDO_TOKEN_PRICE)),
        # _amount_of_tokens_to_sell : Uint256
        *to_uint(int(IDO_TOKENS_TO_SELL)),
        # _sale_end_time : felt
        int(IDO_SALE_END.timestamp()),
        # _tokens_unlock_time : felt
        int(IDO_TOKEN_UNLOCK.timestamp()),
        # _portion_vesting_precision : Uint256
        *to_uint(int(IDO_PORTION_VESTING_PRECISION)),
        # _lottery_tickets_burn_cap : Uint256
        *to_uint(int(IDO_LOTTERY_TOKENS_BURN_CAP))
    ])

    # set IDO vesting parameters
    run_tx(admin_1, ido_contract_full, "set_vesting_params", [
        4,
        *VESTING_TIMES_UNLOCKED,
        *uarr2cd(VESTING_PERCENTAGES),
        0
    ])

    # set IDO registration time
    run_tx(admin_1, ido_contract_full, "set_registration_time", [
        int(REGISTRATION_START.timestamp()), int(REGISTRATION_END.timestamp())])

    print("IDO SUCESSFULLY DEPLOYED 🚀")
