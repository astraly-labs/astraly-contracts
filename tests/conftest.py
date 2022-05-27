import sys
import os
import time
import asyncio
import pytest
import dill
from types import SimpleNamespace

from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starknet.testing.starknet import Starknet, StarknetContract

from utils import Signer, get_block_timestamp, set_block_timestamp

# pytest-xdest only shows stderr
sys.stdout = sys.stderr

CONTRACT_SRC = os.path.join(os.path.dirname(__file__), "..", "contracts")


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


def compile(path):
    return compile_starknet_files(
        files=[os.path.join(CONTRACT_SRC, path)],
        debug_info=True,
        # cairo_path=CONTRACT_SRC,
    )


async def deploy_account(starknet, signer, account_def):
    return await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[signer.public_key],
    )


# StarknetContracts contain an immutable reference to StarknetState, which
# means if we want to be able to use StarknetState's `copy` method, we cannot
# rely on StarknetContracts that were created prior to the copy.
# For this reason, we specifically inject a new StarknetState when
# deserializing a contract.
def serialize_contract(contract, abi):
    return dict(
        abi=abi,
        contract_address=contract.contract_address,
        deploy_execution_info=contract.deploy_execution_info,
    )


def unserialize_contract(starknet_state, serialized_contract):
    return StarknetContract(state=starknet_state, **serialized_contract)


async def build_copyable_deployment():
    starknet = await Starknet.empty()

    # initialize a realistic timestamp
    set_block_timestamp(starknet.state, round(time.time()))

    defs = SimpleNamespace(
        token=compile("ZkPadToken.cairo"),
        lotteryToken=compile("ZkPadLotteryToken.cairo"),
    )

    signers = dict(
        admin=Signer(83745982347),
        unregistered=Signer(69420),
        alice=Signer(7891011),
        bob=Signer(12345),
        carol=Signer(888333444555),
        dave=Signer(897654321),
        eric=Signer(6969),
        frank=Signer(23904852345),
        grace=Signer(215242342),
        hank=Signer(420),
    )

    # Maps from name -> account contract
    accounts = SimpleNamespace(
        **{
            name: (await deploy_account(starknet, signer, defs.account))
            for name, signer in signers.items()
        }
    )

    # Deployment of each contract and set up
    # 1st deploy the token
    token = await starknet.deploy(
        contract_def=defs.token,
        constructor_calldata=[accounts.admin.contract_address])

    async def register_user(account_name):
        # Populate the registry with some data.
        sample_data = 84622096520155505419920978765481155

        # Repeating sample data
        # Indices from 0, 20, 40, 60, 80..., have values 3.
        # Indices from 10, 30, 50, 70, 90..., have values 1.
        # [00010000010011000011] * 6 == [1133] * 6
        # Populate the registry with homogeneous users (same data each).
        await signers[account_name].send_transaction(
            accounts.__dict__[account_name],
            registry.contract_address,
            'register_user',
            [sample_data]
        )

    await register_user("alice")
    await register_user("bob")
    await register_user("carol")
    await register_user("dave")
    await register_user("eric")
    await register_user("frank")
    await register_user("grace")
    await register_user("hank")

    return SimpleNamespace(
        starknet=starknet,
        consts=consts,
        signers=signers,
        serialized_contracts=dict(
            admin=serialize_contract(accounts.admin, defs.account.abi),
            unregistered=serialize_contract(
                accounts.unregistered, defs.account.abi),
            alice=serialize_contract(accounts.alice, defs.account.abi),
            bob=serialize_contract(accounts.bob, defs.account.abi),
            carol=serialize_contract(accounts.carol, defs.account.abi),
            dave=serialize_contract(accounts.dave, defs.account.abi),
            eric=serialize_contract(accounts.eric, defs.account.abi),
            frank=serialize_contract(accounts.frank, defs.account.abi),
            grace=serialize_contract(accounts.grace, defs.account.abi),
            hank=serialize_contract(accounts.hank, defs.account.abi),
            token=serialize_contract(token, defs.token.abi),
        ),
    )


@pytest.fixture(scope="session")
async def copyable_deployment(request):
    CACHE_KEY = "deployment"
    val = request.config.cache.get(CACHE_KEY, None)
    if val is None:
        val = await build_copyable_deployment()
        res = dill.dumps(val).decode("cp437")
        request.config.cache.set(CACHE_KEY, res)
    else:
        val = dill.loads(val.encode("cp437"))
    return val


@pytest.fixture(scope="session")
async def ctx_factory(copyable_deployment):
    serialized_contracts = copyable_deployment.serialized_contracts
    signers = copyable_deployment.signers
    consts = copyable_deployment.consts

    def make():
        starknet_state = copyable_deployment.starknet.state.copy()
        contracts = {
            name: unserialize_contract(starknet_state, serialized_contract)
            for name, serialized_contract in serialized_contracts.items()
        }

        async def execute(account_name, contract_address, selector_name, calldata):
            return await signers[account_name].send_transaction(
                contracts[account_name],
                contract_address,
                selector_name,
                calldata,
            )

        def advance_clock(num_seconds):
            set_block_timestamp(
                starknet_state, get_block_timestamp(
                    starknet_state) + num_seconds
            )

        return SimpleNamespace(
            starknet=Starknet(starknet_state),
            advance_clock=advance_clock,
            consts=consts,
            execute=execute,
            **contracts,
        )

    return make
