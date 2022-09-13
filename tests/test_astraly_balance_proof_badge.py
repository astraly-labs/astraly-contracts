from typing import NamedTuple, List, Callable, Tuple

import pytest
import pytest_asyncio

from dotenv import load_dotenv
from datetime import datetime

from starkware.starknet.services.api.contract_class import ContractClass
from starkware.starknet.testing.state import StarknetState

from signers import MockSigner
from utils import *
from generate_proof_balance import generate_proof, pack_intarray

from starkware.starknet.testing.starknet import Starknet
from starkware.cairo.common.cairo_secp.secp_utils import split
from starkware.starknet.public.abi import get_selector_from_name

account_path = 'openzeppelin/account/presets/Account.cairo'
sbt_contract_factory_path = 'SBT/AstralyBalanceSBTContractFactory.cairo'
balance_proof_badge_path = 'SBT/AstralyBalanceProofBadge.cairo'
mock_L1_headers_store_path = 'mocks/mock_L1_Headers_Store.cairo'

prover = MockSigner(1234321)


@pytest.fixture(scope='session', autouse=True)
def load_env():
    load_dotenv()


@pytest_asyncio.fixture(scope='module')
async def get_starknet() -> Starknet:
    starknet = await Starknet.empty()
    set_block_timestamp(starknet.state, int(
        datetime.today().timestamp()))  # time.time()
    set_block_number(starknet.state, 1)
    return starknet


@pytest.fixture(scope='module')
def contract_defs() -> Tuple[ContractClass, ContractClass, ContractClass, ContractClass]:
    account_def = get_contract_def(account_path)
    sbt_contract_factory_def = get_contract_def(
        sbt_contract_factory_path, disable_hint_validation=True)
    balance_proof_badge_def = get_contract_def(
        balance_proof_badge_path, disable_hint_validation=True)
    mock_L1_headers_store_def = get_contract_def(
        mock_L1_headers_store_path, disable_hint_validation=True)
    return account_def, sbt_contract_factory_def, balance_proof_badge_def, mock_L1_headers_store_def


@pytest_asyncio.fixture(scope='module')
async def contacts_init(contract_defs, get_starknet: Starknet) -> Tuple[
    StarknetContract, StarknetContract, StarknetContract]:
    starknet = get_starknet
    account_def, sbt_contract_factory_def, balance_proof_badge_def, mock_L1_headers_store_def = contract_defs
    await starknet.declare(contract_class=account_def)
    prover_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[prover.public_key],
        disable_hint_validation=True,
        contract_address_salt=prover.public_key
    )

    await starknet.declare(contract_class=sbt_contract_factory_def)
    sbt_contract_factory = await starknet.deploy(
        contract_class=sbt_contract_factory_def,
        constructor_calldata=[],
        disable_hint_validation=True
    )

    await starknet.declare(contract_class=mock_L1_headers_store_def)
    mock_L1_headers_store = await starknet.deploy(
        contract_class=mock_L1_headers_store_def,
        constructor_calldata=[],
        disable_hint_validation=True
    )

    balance_proof_class_hash = await starknet.declare(contract_class=balance_proof_badge_def)

    await prover.send_transaction(prover_account, sbt_contract_factory.contract_address, "initializer",
                                  [balance_proof_class_hash.class_hash, prover_account.contract_address,
                                   mock_L1_headers_store.contract_address])

    return prover_account, sbt_contract_factory, mock_L1_headers_store


@pytest.fixture
def contracts_factory(contract_defs, contacts_init, get_starknet: Starknet) -> Tuple[
    StarknetContract, StarknetContract, StarknetContract, StarknetState]:
    account_def, sbt_contract_factory_def, _, mock_L1_headers_store_def = contract_defs
    prover_account, sbt_contract_factory, mock_L1_headers_store = contacts_init
    _state = get_starknet.state.copy()

    prover_cached = cached_contract(
        _state, account_def, prover_account)
    sbt_contract_factory_cached = cached_contract(
        _state, sbt_contract_factory_def, sbt_contract_factory)
    mock_L1_headers_store_cached = cached_contract(
        _state, mock_L1_headers_store_def, mock_L1_headers_store)

    return prover_cached, sbt_contract_factory_cached, mock_L1_headers_store_cached, _state


@pytest.mark.asyncio
async def test_create_sbt_contract_function(contracts_factory, contract_defs):
    prover_account, sbt_contract_factory, _, starknet_state = contracts_factory
    _, _, balance_proof_badge_def, _ = contract_defs
    erc20_token = "0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72"
    block_number = 7415645
    min_balance = 1
    create_sbt_transaction_receipt = await prover.send_transaction(prover_account,
                                                                   sbt_contract_factory.contract_address,
                                                                   "createSBTContract",
                                                                   [block_number, min_balance, int(erc20_token, 16)])

    balance_proof_badge_contract = StarknetContract(starknet_state, balance_proof_badge_def.abi,
                                                    create_sbt_transaction_receipt.result.response[0], None)

    assert min_balance == (await balance_proof_badge_contract.minBalance().call()).result.min
    assert int(erc20_token, 16) == (await balance_proof_badge_contract.tokenAddress().call()).result.address


@pytest.mark.asyncio
async def test_proof(contracts_factory, contract_defs):
    prover_account, sbt_contract_factory, mock_L1_headers_store_cached, starknet_state = contracts_factory
    _, _, balance_proof_badge_def, _ = contract_defs

    LINK_token_address = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB"
    block_number = 7486880
    min_balance = 1

    ethereum_address = "0x4Db4bB41758F10D97beC54155Fdb59b879207F92"
    ethereum_pk = "eb5a6c2a9e46618a92b40f384dd9e076480f1b171eb21726aae34dc8f22fe83f"
    rpc_node = "https://eth-goerli.g.alchemy.com/v2/uXpxHR8fJBH3fjLJpulhY__jXbTGNjN7"
    storage_slot = hex(1)
    proof = generate_proof(ethereum_address, ethereum_pk, hex(prover_account.contract_address), rpc_node, storage_slot,
                           LINK_token_address, block_number)

    args = list()
    args.append(prover_account.contract_address)
    args.append(proof['balance'])
    args.append(proof['nonce'])
    args.append(len(proof['accountProof']))
    args.append(len(proof['storageProof'][0]['proof']))

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
    args.append(len(proof['signature']['message'][2:]) // 2)

    R_x_ = split(proof['signature']['R_x'])
    args.append(len(R_x_))  # R_x__len
    args += R_x_

    R_y_ = split(proof['signature']['R_y'])
    args.append(len(R_y_))  # R_y__len
    args += R_y_

    s_ = split(proof['signature']['s'])
    args.append(len(s_))  # s__len
    args += s_

    args.append(proof['signature']['v'])

    storage_key_ = pack_intarray(proof['storageProof'][0]['key'])
    args.append(len(storage_key_))  # storage_key__len
    args += storage_key_

    storage_value_ = pack_intarray(hex(proof['storage_value']))
    args.append(len(storage_value_))  # storage_value__len
    args += storage_value_

    class IntsSequence(NamedTuple):
        values: List[int]
        length: int

    chunk_bytes_input: Callable[[bytes], List[bytes]] = lambda input: [
        input[i + 0:i + 8] for i in range(0, len(input), 8)]

    def to_ints(input: str) -> IntsSequence:
        bytes_input = bytes.fromhex(input[2:])
        chunked = chunk_bytes_input(bytes_input)
        ints_array = list(
            map(lambda chunk: int.from_bytes(chunk, 'big'), chunked))
        return IntsSequence(values=ints_array, length=len(bytes_input))

    account_proof = list(map(lambda element: to_ints(
        element), proof['accountProof']))

    flat_account_proof = []
    flat_account_proof_sizes_bytes = []
    flat_account_proof_sizes_words = []
    for proof_element in account_proof:
        flat_account_proof += proof_element.values
        flat_account_proof_sizes_bytes += [proof_element.length]
        flat_account_proof_sizes_words += [len(proof_element.values)]

    args.append(len(flat_account_proof))
    args += flat_account_proof

    args.append(len(flat_account_proof_sizes_words))
    args += flat_account_proof_sizes_words

    args.append(len(flat_account_proof_sizes_bytes))
    args += flat_account_proof_sizes_bytes

    storage_proof = list(map(lambda element: to_ints(
        element), proof['storageProof'][0]['proof']))

    flat_storage_proof = []
    flat_storage_proof_sizes_bytes = []
    flat_storage_proof_sizes_words = []
    for proof_element in storage_proof:
        flat_storage_proof += proof_element.values
        flat_storage_proof_sizes_bytes += [proof_element.length]
        flat_storage_proof_sizes_words += [len(proof_element.values)]

    args.append(len(flat_storage_proof))
    args += flat_storage_proof

    args.append(len(flat_storage_proof_sizes_words))
    args += flat_storage_proof_sizes_words

    args.append(len(flat_storage_proof_sizes_bytes))
    args += flat_storage_proof_sizes_bytes

    state_root = pack_intarray(proof['stateRoot'])
    await prover.send_transaction(prover_account, mock_L1_headers_store_cached.contract_address, "set_state_root",
                                  [len(state_root), *state_root, block_number])

    create_sbt_transaction_receipt = await prover.send_transaction(prover_account,
                                                                   sbt_contract_factory.contract_address,
                                                                   "createSBTContract",
                                                                   [block_number, min_balance,
                                                                    int(LINK_token_address, 16)])

    balance_proof_badge_contract = StarknetContract(starknet_state, balance_proof_badge_def.abi,
                                                    create_sbt_transaction_receipt.result.response[0], None)

    receipt = await prover.send_transaction(prover_account, balance_proof_badge_contract.contract_address, "mint",
                                            [*args])

    event_signature = get_selector_from_name("Transfer")
    assert next(
        (x for x in receipt.raw_events if event_signature in x.keys), None) is not None
