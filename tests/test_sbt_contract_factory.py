from datetime import datetime
from math import ceil

import pytest
import pytest_asyncio

from signers import MockSigner
from utils import *
import asyncio
from generate_proof_balance import generate_proof, pack_intarray

from starkware.starknet.testing.starknet import Starknet

account_path = 'openzeppelin/account/presets/Account.cairo'
sbt_contract_factory_path = 'SBT/AstralyBalanceSBTContractFactory.cairo'
balance_proof_badge_path = 'SBT/AstralyBalanceProofBadge.cairo'

prover = MockSigner(1234321)


@pytest_asyncio.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    set_block_timestamp(starknet.state, int(
        datetime.today().timestamp()))  # time.time()
    set_block_number(starknet.state, 1)
    return starknet


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def(account_path)
    sbt_contract_factory_def = get_contract_def(sbt_contract_factory_path)
    balance_proof_badge_def = get_contract_def(balance_proof_badge_path)
    return account_def, sbt_contract_factory_def, balance_proof_badge_def


@pytest_asyncio.fixture(scope='module')
async def contacts_init(contract_defs, get_starknet):
    starknet = get_starknet
    account_def, sbt_contract_factory_def, balance_proof_badge_def = contract_defs
    await starknet.declare(contract_class=account_def)
    prover_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[prover.public_key]
    )

    await starknet.declare(contract_class=sbt_contract_factory_def)
    sbt_contract_factory = await starknet.deploy(
        contract_class=sbt_contract_factory_def,
        constructor_calldata=[]
    )

    balance_proof_class_hash = await starknet.declare(contract_class=balance_proof_badge_def)

    await prover.send_transaction(prover_account, sbt_contract_factory.contract_address, "initializer",
                                  [balance_proof_class_hash.class_hash, prover_account.contract_address])

    return prover_account, sbt_contract_factory


@pytest.fixture
def contracts_factory(contract_defs, contacts_init, get_starknet):
    account_def, sbt_contract_factory_def, _ = contract_defs
    prover_account, sbt_contract_factory = contacts_init
    _state = get_starknet.state.copy()

    prover_cached = cached_contract(
        _state, account_def, prover_account)
    sbt_contract_factory_cached = cached_contract(
        _state, sbt_contract_factory_def, sbt_contract_factory)

    return prover_cached, sbt_contract_factory_cached, _state


@pytest.mark.asyncio
async def test_proof(contracts_factory, contract_defs):
    prover_account, sbt_contract_factory, starknet_state = contracts_factory
    _, _, balance_proof_badge_def = contract_defs

    erc20_token = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB"

    block_number = 7415645
    min_balance = 1
    create_sbt_transaction_receipt = await prover.send_transaction(prover_account,
                                                                   sbt_contract_factory.contract_address,
                                                                   "createSBTContract",
                                                                   [block_number, min_balance, int(erc20_token, 16)])

    balance_proof_badge_contract = StarknetContract(starknet_state, sbt_contract_factory.abi,
                                                    create_sbt_transaction_receipt.result.response[0], None)

    ethereum_address = "0x4Db4bB41758F10D97beC54155Fdb59b879207F92"
    ethereum_pk = "eb5a6c2a9e46618a92b40f384dd9e076480f1b171eb21726aae34dc8f22fe83f"
    LINK_token_address = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB"
    rpc_node = "https://eth-goerli.g.alchemy.com/v2/uXpxHR8fJBH3fjLJpulhY__jXbTGNjN7"
    storage_slot = hex(1)
    proof = generate_proof(ethereum_address, ethereum_pk, hex(prover_account.contract_address), rpc_node, storage_slot,
                           LINK_token_address, block_number)

    args = list()
    args.append(prover_account.contract_address)
    args.append(proof['storage_value']) # token balance
    args.append(proof['balance'])
    args.append(proof['nonce'])
    args.append(starknet_state.general_config.chain_id.value)
    args.append(starknet_state.state.block_info.block_number)
    args.append(len(proof['accountProof']))
    args.append(len(proof['storageProof'][0]['proof']))

    address_ = pack_intarray(proof['address'])
    args.append(len(address_))  # address__len
    args += address_

    state_root = pack_intarray(proof['stateRoot'])
    args.append(len(state_root))  # state_root__len
    args += state_root

    code_hash_ = pack_intarray(proof['codeHash'])
    args.append(len(code_hash_))  # code_hash__len
    args += code_hash_

    storage_slot_ = pack_intarray(proof['storageSlot'])
    args.append(len(storage_slot_))  # storage_slot__len
    args += storage_slot_

    storage_hash_ = pack_intarray(proof['storageHash'])
    args.append(len(storage_hash_))  # storage_hash__len
    args += storage_hash_

    message_ = pack_intarray(proof['signature']['message'])
    args.append(len(message_))  # message__len
    args += message_
    args.append(len(proof['signature']['message'][2:]))

    R_x_ = pack_intarray(hex(proof['signature']['R_x']))
    args.append(len(R_x_))  # R_x__len
    args += R_x_

    R_y_ = pack_intarray(hex(proof['signature']['R_y']))
    args.append(len(R_y_))  # R_y__len
    args += R_y_

    s_ = pack_intarray(hex(proof['signature']['s']))
    args.append(len(s_))  # s__len
    args += s_
    args.append(proof['signature']['v'])

    storage_key_ = pack_intarray(proof['storage_key'])
    args.append(len(storage_key_))  # storage_key__len
    args += storage_key_

    storage_value_ = pack_intarray(hex(proof['storage_value']))
    args.append(len(storage_value_))  # storage_value__len
    args += storage_value_

    # calculate
    args.append(0)
    args.append(0)
    args.append(0)
    args.append(0)
    args.append(0)
    args.append(0)


    receipt = await prover.send_transaction(prover_account, balance_proof_badge_contract.contract_address, "mint",
                                            [*args])
