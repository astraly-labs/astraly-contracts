from ast import alias, arguments
import os
from datetime import datetime, timedelta
import time

from nile.nre import NileRuntimeEnvironment


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
os.environ["SIGNER"] = "123456"
os.environ["USER_1"] = "12345654321"

os.environ["ADMIN_1"] = "23456765432"
os.environ["ADMIN_2"] = "34567876543"
os.environ["NUMBER_OF_ADMINS"] = "2"
os.environ["XOROSHIRO_RNG_SEED"] = "984375843"

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

    # deploy admin contract
    admin_contract = None
    try:
        admin_contract, admin_contract_abi = nre.deploy(
            "ZkPadAdmin",
            arguments=[
                os.environ.get("NUMBER_OF_ADMINS"),
                *[admin_1.address, admin_2.address]
            ],
            alias="admin_contract"
        )
    except Exception as error:
        if "already exists" in str(error):
            admin_contract, admin_contract_abi = nre.get_deployment(
                "admin_contract")
        else:
            print(f"ADMIN Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed Admin to {admin_contract}")

    # deploy random nunber generator contract
    xoroshiro_contract = None
    try:
        xoroshiro_contract, xoroshiro_contract_abi = nre.deploy(
            "xoroshiro128_starstar",
            arguments=[
                os.environ.get("XOROSHIRO_RNG_SEED")
            ],
            alias="xoroshiro_contract"
        )
    except Exception as error:
        if "already exists" in str(error):
            xoroshiro_contract, xoroshiro_contract_abi = nre.get_deployment(
                "xoroshiro_contract")
        else:
            print(f"XOROSHIRO Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed xoroshiro to {xoroshiro_contract}")

    # Deploy IDO Factory
    factory_contract = None
    try:
        factory_contract, abi = nre.deploy(
            "ZkPadIDOFactory_mock", arguments=[], alias="factory_contract")

    except Exception as error:
        if "already exists" in str(error):
            factory_contract, abi = nre.get_deployment("factory_contract")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed IDO Factory to {factory_contract}")

    # Deploy Lottery token
    lottery_token = None
    try:
        lottery_token, abi = nre.deploy("ZkPadLotteryToken", arguments=[
            "0", signer.address, factory_contract
        ], alias="lottery_token")

    except Exception as error:
        if "already exists" in str(error):
            lottery_token, abi = nre.get_deployment("lottery_token")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed Lottery token to {lottery_token}")

    zkp_token, zkp_token_abi = nre.get_deployment("zkp_token")

    # deploy Task contract
    task_contract = None
    try:
        task_contract, task_contract_abi = nre.deploy(
            "ZkPadTask",
            arguments=[
                factory_contract
            ],
            alias="task_contract"
        )
    except Exception as error:
        if "already exists" in str(error):
            task_contract, task_contract_abi = nre.get_deployment(
                "task_contract")
        else:
            print(f"TASK Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed task contract to {task_contract}")

    # deploy IDO contract
    ido_contract_full = None
    try:
        ido_contract_full, ido_contract_abi = nre.deploy(
            "ZkPadIDOContract",
            arguments=[
                admin_contract,
                factory_contract
            ],
            alias="ido_contract_full"
        )
    except Exception as error:
        if "already exists" in str(error):
            ido_contract_full, ido_contract_abi = nre.get_deployment(
                "ido_contract_full")
        else:
            print(f"IDO Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed ido to {ido_contract_full}")

    print("Done...")
