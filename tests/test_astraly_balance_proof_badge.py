from datetime import datetime

import pytest

from signers import MockSigner
from utils import *
import asyncio
import csv

from starkware.starknet.testing.starknet import Starknet

account_path = 'openzeppelin/account/presets/Account.cairo'
contract_path = 'SBTs/AstralyBalanceProofBadge.cairo'
with open('tests/proof.csv', newline='') as csvfile:
    proof = list(csv.reader(csvfile))[0]

prover = MockSigner(1234321)


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
    prover_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[prover.public_key]
    )

    await starknet.declare(contract_class=balance_proof_badge_def)
    balance_proof_badge = await starknet.deploy(
        contract_class=balance_proof_badge_def,
        constructor_calldata=[]
    )

    return prover_account, balance_proof_badge


@pytest.fixture
def contracts_factory(contract_defs, contacts_init, get_starknet):
    account_def, balance_proof_badge_def = contract_defs
    prover_account, balance_proof_badge = contacts_init
    _state = get_starknet.state.copy()

    prover_cached = cached_contract(
        _state, account_def, prover_account)
    balance_proof_badge_cached = cached_contract(
        _state, balance_proof_badge_def, balance_proof_badge)

    return prover_cached, balance_proof_badge_cached, _state


@pytest.mark.asyncio
async def test_proof(contracts_factory):
    prover_account, balance_proof_badge, starknet_state = contracts_factory

    await prover_account.mint(*balance_proof_badge).invoke()
