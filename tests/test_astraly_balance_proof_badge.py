import pytest
from utils import *
import asyncio
import json

from starkware.starknet.testing.starknet import Starknet

account_path = 'openzeppelin/account/Account.cairo'
contract_path = 'SBTs/AstralyBalanceProofBadge.cairo'
proof = json.load(open("tests/proof.json"))


proover = Signer(1234321)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    set_block_timestamp(starknet.state, int(
        datetime.today().timestamp()))  # time.time()
    return starknet


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def(account_path)
    balance_proof_badge = get_contract_def(contract_path)
    return account_def, balance_proof_badge


@pytest.fixture(scope='module')
async def contacts_init(contract_defs, get_starknet):
    starknet = get_starknet
    account_def, balance_proof_badge_def = contract_defs
    await starknet.declare(contract_class=account_def)
    proover_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[deployer.public_key]
    )

    await starknet.declare(contract_class=balance_proof_badge_def)
    balance_proof_badge = await starknet.deploy(
        contract_class=balance_proof_badge_def,
        constructor_calldata=[123]
    )

    return proover_account, balance_proof_badge


@pytest.fixture
def contracts_factory(contract_defs, contacts_init, get_starknet):
    account_def, balance_proof_badge_def = contract_defs
    proover_account, balance_proof_badge = contacts_init
    _state = get_starknet.state.copy()

    proover_cached = cached_contract(
        _state, account_def, proover_account)
    balance_proof_badge_cached = cached_contract(
        _state, balance_proof_badge_def, balance_proof_badge)

    return proover_cached, balance_proof_badge_cached, _state


@pytest.mark.asyncio
async def test_winning_tickets(contracts_factory):
    proover_account, balance_proof_badge, starknet_state = contracts_factory
