import os
import sys
from nile.nre import NileRuntimeEnvironment


from datetime import datetime, timedelta
import time

sys.path.append(os.path.dirname(__file__))
from utils import deploy_try_catch


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


def parse_ether(value: int):
    return int(value * 1e18)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


# dotenv.load_dotenv()
# Dummy values, should be replaced by env variables
# os.environ["SIGNER"] = "123456"
# os.environ["USER_1"] = "12345654321"

# os.environ["ADMIN_1"] = "23456765432"
# os.environ["ADMIN_2"] = "34567876543"
# os.environ["NUMBER_OF_ADMINS"] = "2"
# os.environ["XOROSHIRO_RNG_SEED"] = "984375843"

# ZKP TOKEN PARAMS
INITIAL_SUPPLY = str(parse_ether(10_000_000))  # TODO: check value before deploy
MAX_SUPPLY = str(parse_ether(100_000_000))  # TODO: check value before deploy
DECIMALS = "18"
NAME = str_to_felt("ZkPad")
SYMBOL = str_to_felt("ZKP")

# XZKP TOKEN PARAMS
XZKP_NAME = str_to_felt("xZkPad")
XZKP_SYMBOL = str_to_felt("xZKP")
REWARDS_PER_BLOCK = to_uint(parse_ether(10))
START_BLOCK = 0
END_BLOCK = START_BLOCK + 10000

# LOTTERY TOKEN PARAMS
lottery_uri = [str(str_to_felt("ipfs://")), str(str_to_felt("dfsffds"))]

# IDO PARAMS
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

    # Deploy ZKP token
    zkp_token = deploy_try_catch(nre, "ZkPadToken", [
        str(NAME),
        str(SYMBOL),
        DECIMALS,
        INITIAL_SUPPLY,
        "0",
        "0x970e62cb92ae24fb6f1ea455407edf6cb0f3b739940b4dffbf976b65d7830a",
        signer.address,
        MAX_SUPPLY,
        "0"
    ], "zkp_token")
    # xzkp_token_implementation = deploy_try_catch(
    #     nre, "ZkPadStaking", [], "xzkp_token_implementation")
    xzkp_class_hash = nre.declare("ZkPadStaking")
    xzkp_token = deploy_try_catch(
        nre, "Proxy", [xzkp_class_hash], "xzkp_token_proxy")

    # deploy harvest task
    harvest_task = deploy_try_catch(
        nre, "ZkPadVaultHarvestTask", [xzkp_token], "harvest_task")

    # deploy admin contract
    admin_contract = deploy_try_catch(nre, "ZkPadAdmin", [
        os.environ.get("NUMBER_OF_ADMINS"),
        *[admin_1.address, admin_2.address]
    ], "admin_contract")

    # deploy random number generator contract
    xoroshiro_contract = deploy_try_catch(
        nre, "xoroshiro128_starstar", [
            os.environ.get("XOROSHIRO_RNG_SEED")
        ], "xoroshiro_contract")

    # Deploy IDO Factory
    ido_class_hash = nre.declare("ZkPadIDOContract", alias="ZkPadIDOContract")
    factory_contract = deploy_try_catch(
        nre, "ZkPadIDOFactory", [ido_class_hash, signer.address], "factory_contract")

    # Deploy Lottery token
    lottery_token = deploy_try_catch(nre, "ZkPadLotteryToken", [
        str(len(lottery_uri)), *lottery_uri, signer.address, factory_contract
    ], "lottery_token")

    # Deploy IDO Task
    task_contract = deploy_try_catch(nre, "ZkPadTask", [
        factory_contract
    ], "task_contract")

    print("CONTRACTS DEPLOYMENT DONE 🚀")
