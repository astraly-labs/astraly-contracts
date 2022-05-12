from ast import alias, arguments
import os
from datetime import datetime, timedelta

from nile.nre import NileRuntimeEnvironment

# Dummy values, should be replaced by env variables
os.environ["SIGNER"]  = "123456"
os.environ["USER_1"]  = "12345654321"

os.environ["ADMIN_1"] = "23456765432"
os.environ["ADMIN_2"] = "34567876543"
os.environ["NUMBER_OF_ADMINS"] = "2"

os.environ["XOROSHIRO_RNG_SEED"] = "984375843"

os.environ["IDO_TOKEN_PRICE"]               = "10000000000000000" # 0.01 ETH
os.environ["IDO_TOKENS_TO_SELL"]            = "100000000000000000000000" # 100,000 TOKENS
os.environ["IDO_PORTION_VESTING_PRECISION"] = "1000" # vestion portion percentages must add up to 1000 
os.environ["IDO_LOTTERY_TOKENS_BURN_CAP"]   = "10000" # users can't burn more than 10000 lottery tickets


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

def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    admin_1 = nre.get_or_deploy_account("ADMIN_1")
    admin_2 = nre.get_or_deploy_account("ADMIN_2")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")
    print(f"Admin1 account: {admin_1.address}")
    print(f"Admin2 account: {admin_2.address}")

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
            admin_contract, admin_contract_abi = nre.get_deployment("admin_contract")
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
            xoroshiro_contract, xoroshiro_contract_abi = nre.get_deployment("xoroshiro_contract")
        else:
            print(f"XOROSHIRO Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed xoroshiro to {xoroshiro_contract}")    

    factory_contract, factory_contract_abi = nre.get_deployment("factory_contract")
    lottery_token, lottery_token_abi = nre.get_deployment("lottery_token")
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
            task_contract, task_contract_abi = nre.get_deployment("task_contract")
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
            ido_contract_full, ido_contract_abi = nre.get_deployment("ido_contract_full")
        else:
            print(f"IDO Contract DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed ido to {ido_contract_full}")

    # set IDO Factory contract variables
    signer.send(factory_contract, "set_task_address",
        [int(task_contract, 16)]
    )
    
    signer.send(factory_contract, "create_ido", 
        [int(ido_contract_full, 16)]
    )

    signer.send(factory_contract, "set_lottery_ticket_contract_address", 
        [int(lottery_token, 16)]
    )

    day = datetime.today()
    timeDelta30days = timedelta(days=30)
    timeDeltaOneWeek = timedelta(weeks=1)

    sale_end = day + timeDelta30days
    token_unlock = sale_end + timeDeltaOneWeek

    # set IDO contract sale parameters
    admin_1.send(ido_contract_full, "set_sale_params", 
        [
            int(zkp_token, 16),                     # _token_address : felt
            int(signer.address, 16),                # _sale_owner_address : felt
            *to_uint(int(os.environ.get("IDO_TOKEN_PRICE"))),       # _token_price : Uint256
            *to_uint(int(os.environ.get("IDO_TOKENS_TO_SELL"))),    # _amount_of_tokens_to_sell : Uint256
            int(sale_end.timestamp()),              # _sale_end_time : felt
            int(token_unlock.timestamp()),          # _tokens_unlock_time : felt
            *to_uint(int(os.environ.get("IDO_PORTION_VESTING_PRECISION"))),  # _portion_vesting_precision : Uint256
            *to_uint(int(os.environ.get("IDO_LOTTERY_TOKENS_BURN_CAP")))     # _lottery_tickets_burn_cap : Uint256            
        ]
    )

    # set IDO vesting parameters
    VESTING_PERCENTAGES = uint_array([100, 200, 300, 400])

    VESTING_TIMES_UNLOCKED = [
        int(token_unlock.timestamp()) + (1 * 24 * 60 * 60), # 1 day after tokens unlock time
        int(token_unlock.timestamp()) + (8 * 24 * 60 * 60), # 8 days after tokens unlock time
        int(token_unlock.timestamp()) + (15 * 24 * 60 * 60),# 15 days after tokens unlock time
        int(token_unlock.timestamp()) + (22 * 24 * 60 * 60) # 22 days after tokens unlock time
    ]

    admin_1.send(ido_contract_full, "set_vesting_params", 
        [
            4,
            *VESTING_TIMES_UNLOCKED,
            *uarr2cd(VESTING_PERCENTAGES),
            0
        ]
    )




