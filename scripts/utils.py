from nile.nre import NileRuntimeEnvironment
from nile.core.account import Account

import re
import subprocess


def deploy_try_catch(nre: NileRuntimeEnvironment, name: str, params, alias: str):
    contract = None
    try:
        contract, abi = nre.deploy(
            name, arguments=params, alias=alias)

    except Exception as error:
        if "already exists" in str(error):
            contract, abi = nre.get_deployment(alias)
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed {name} to {contract}")

    return contract

def run_tx(account: Account, contract, selector: str, calldata):
    tx = account.send(contract, selector, calldata)
    tx_hash = re.split("Transaction hash: ", tx)[-1]
    print(f"Running {selector}. [hash]: {tx_hash}")
    subprocess.check_output(['nile', 'debug', tx_hash])
