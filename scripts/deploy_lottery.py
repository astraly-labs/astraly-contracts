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

    # Deploy Mock IDO
    # ido_contract = None
    # try:
    #     ido_contract, abi = nre.deploy(
    #         "ZkPadIDOContract_mock", arguments=[], alias="ido_contract")

    # except Exception as error:
    #     if "already exists" in str(error):
    #         ido_contract, abi = nre.get_deployment("ido_contract")
    #     else:
    #         print(f"DEPLOYMENT ERROR: {error}")
    # finally:
    #     print(f"Deployed IDO to {ido_contract}")

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

    # signer.send(factory_contract, "create_ido", [])

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

    signer.send(lottery_token, "set_xzkp_contract_address",
                [int(xzkp_token, 16)])
    signer.send(lottery_token, "set_ido_factory_address",
                [int(factory_contract, 16)])
