"""Utilities for testing Cairo contracts."""
from collections import namedtuple
from pathlib import Path
from functools import cache
import math

from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.crypto.signature.signature import private_to_stark_key, sign
from starkware.starknet.business_logic.state.state import BlockInfo
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import StarknetContract
from starkware.starknet.business_logic.execution.objects import Event, OrderedEvent
from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash
from starkware.starknet.business_logic.transaction.objects import InternalTransaction, TransactionExecutionInfo


from nile.utils import felt_to_str, str_to_felt, to_uint, from_uint, add_uint, sub_uint, mul_uint, div_rem_uint, assert_revert
from nile.signer import Signer

MAX_UINT256 = (2**128 - 1, 2**128 - 1)
INVALID_UINT256 = (MAX_UINT256[0] + 1, MAX_UINT256[1])
ZERO_ADDRESS = 0
TRUE = 1
FALSE = 0

TRANSACTION_VERSION = 0

_root = Path(__file__).parent.parent


def contract_path(name):
    if name.startswith("openzeppelin"):
        return str(_root / "lib/cairo_contracts/src" / name)
    elif name.startswith("tests/"):
        return str(_root / name)
    elif name.startswith("/"):
        return str(_root / "contracts" / name[1:])
    else:
        return str(_root / "contracts" / name)


def get_contract_class(path):
    """Return the contract class from the contract path"""
    path = contract_path(path)
    contract_class = compile_starknet_files(
        files=[path], debug_info=True, disable_hint_validation=True
    )
    return contract_class


def uint(a):
    return (a, 0)


def assert_event_emitted(tx_exec_info, from_address, name, data, order=0):
    """Assert one single event is fired with correct data."""
    assert_events_emitted(tx_exec_info, [(order, from_address, name, data)])


def assert_events_emitted(tx_exec_info: TransactionExecutionInfo, events):
    """Assert events are fired with correct data."""
    for event in events:
        order, from_address, name, data = event
        event_obj = OrderedEvent(
            order=order,
            keys=[get_selector_from_name(name)],
            data=data,
        )

        base = tx_exec_info.call_info.internal_calls[0]
        # print(base.events, event_obj)
        if event_obj in base.events and from_address == base.contract_address:
            return

        try:
            base2 = base.internal_calls[0]
            if event_obj in base2.events and from_address == base2.contract_address:
                return
        except IndexError:
            pass

        raise BaseException("Event not fired or not fired correctly")


@cache
def get_contract_def(path):
    """Returns the contract definition from the contract path"""
    path = contract_path(path)
    contract_def = compile_starknet_files(
        files=[path],
        debug_info=True,
        cairo_path=[
            str(_root / "lib/cairo_contracts/src"),
            str(_root / "lib/starknet_attestations"),
        ],
        disable_hint_validation=True,
    )
    return contract_def


def cached_contract(state, definition, deployed):
    """Returns the cached contract"""
    contract = StarknetContract(
        state=state,
        abi=definition.abi,
        contract_address=deployed.contract_address,
        deploy_call_info=deployed.deploy_call_info,
    )
    return contract


def get_block_timestamp(starknet_state):
    return starknet_state.state.block_info.block_timestamp


def set_block_timestamp(starknet_state, timestamp):
    starknet_state.state.block_info = BlockInfo.create_for_testing(
        starknet_state.state.block_info.block_number, timestamp
    )


def get_block_number(starknet_state):
    return starknet_state.state.block_info.block_number


def set_block_number(starknet_state, block_number):
    starknet_state.state.block_info = BlockInfo.create_for_testing(
        block_number, starknet_state.state.block_info.block_timestamp
    )


def advance_clock(starknet_state, num_seconds):
    set_block_timestamp(
        starknet_state, get_block_timestamp(starknet_state) + num_seconds
    )


def days_to_seconds(days: int):
    return days * 24 * 60 * 60


def assert_approx_eq(a: int, b: int, max_delta: int):
    delta = a - b if a > b else b - a

    if delta > max_delta:
        print(f"a: {a}")
        print(f"b: {b}")
        print(f"delta: {delta}")
        assert False
    assert True


def uint_array(l):
    return list(map(to_uint, l))


def uarr2cd(arr):
    acc = [len(arr)]
    for lo, hi in arr:
        acc.append(lo)
        acc.append(hi)
    return acc


def get_next_level(level):
    next_level = []

    for i in range(0, len(level), 2):
        node = 0
        if level[i] < level[i + 1]:
            node = pedersen_hash(level[i], level[i + 1])
        else:
            node = pedersen_hash(level[i + 1], level[i])

        next_level.append(node)

    return next_level


def generate_proof_helper(level, index, proof):
    if len(level) == 1:
        return proof
    if len(level) % 2 != 0:
        level.append(0)

    next_level = get_next_level(level)
    index_parent = 0

    for i in range(0, len(level)):
        if i == index:
            index_parent = i // 2
            if i % 2 == 0:
                proof.append(level[index + 1])
            else:
                proof.append(level[index - 1])

    return generate_proof_helper(next_level, index_parent, proof)


def generate_merkle_proof(values, index):
    return generate_proof_helper(values, index, [])


def generate_merkle_root(values):
    if len(values) == 1:
        return values[0]

    if len(values) % 2 != 0:
        values.append(0)

    next_level = get_next_level(values)
    return generate_merkle_root(next_level)


def verify_merkle_proof(leaf, proof):
    root = proof[len(proof) - 1]
    proof = proof[:-1]
    curr = leaf

    for proof_elem in proof:
        if curr < proof_elem:
            curr = pedersen_hash(curr, proof_elem)
        else:
            curr = pedersen_hash(proof_elem, curr)

    return curr == root


def get_leaf(recipient, amount):
    # amount_hash = pedersen_hash(amount, 0)
    leaf = pedersen_hash(recipient, amount)
    return leaf


# creates the inital merkle leaf values to use


def get_leaves(recipients, amounts):
    values = []
    for i in range(0, len(recipients)):
        leaf = get_leaf(recipients[i], amounts[i])
        value = (leaf, recipients[i], amounts[i])
        values.append(value)

    if len(values) % 2 != 0:
        last_value = (0, 0, 0)
        values.append(last_value)

    return values
