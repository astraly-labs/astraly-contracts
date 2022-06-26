import pytest
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import Starknet
from utils import *
import asyncio


def uint_array(l):
    return list(map(uint, l))


def uarr2cd(arr):
    acc = [len(arr)]
    for lo, hi in arr:
        acc.append(lo)
        acc.append(hi)
    return acc


def get_block_timestamp(starknet_state):
    return starknet_state.state.block_info.block_timestamp


def set_block_timestamp(starknet_state, timestamp):
    starknet_state.state.block_info = BlockInfo(
        starknet_state.state.block_info.block_number, timestamp
    )


INIT_SUPPLY = to_uint(1_000_000)
CAP = to_uint(1_000_000_000_000)
UINT_ONE = to_uint(1)
UINT_ZERO = to_uint(0)
NAME = str_to_felt("xZkPad")
SYMBOL = str_to_felt("xZKP")
DECIMALS = 18

# Vesting Params
vesting_len = 2
shares = uint_array([500, 500])
amount_vested = to_uint(100_000_000_000_000_000_000)
duration_seconds = 4 * 365 * 86400

owner = Signer(1234)
user1 = Signer(2345)
user2 = Signer(3456)
user3 = Signer(4567)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def('openzeppelin/account/Account.cairo')
    zk_pad_token_def = get_contract_def('ZkPadToken.cairo')
    vesting_def = get_contract_def('ZkPadVesting.cairo')
    return account_def, zk_pad_token_def, vesting_def


@pytest.fixture(scope='module')
async def contracts_init(contract_defs):
    starknet = await Starknet.empty()
    account_def, zk_pad_token_def, vesting_def = contract_defs
    await starknet.declare(contract_class=account_def)
    owner_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[owner.public_key]
    )
    user1_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[user1.public_key]
    )
    user2_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[user2.public_key]
    )
    user3_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[user3.public_key]
    )
    await starknet.declare(contract_class=zk_pad_token_def)
    zk_pad_token = await starknet.deploy(
        contract_class=zk_pad_token_def,
        constructor_calldata=[
            str_to_felt("ZkPad"),
            str_to_felt("ZKP"),
            DECIMALS,
            *INIT_SUPPLY,
            owner_account.contract_address,  # recipient
            owner_account.contract_address,  # owner
            *CAP,
        ],
    )

    _start_timestamp = get_block_timestamp(starknet.state) + 3600

    await starknet.declare(contract_class=vesting_def)
    zk_pad_vesting = await starknet.deploy(
        contract_class=vesting_def,
        constructor_calldata=[
            vesting_len, user1_account.contract_address,
            user2_account.contract_address, *uarr2cd(shares),
            _start_timestamp, duration_seconds, zk_pad_token.contract_address
        ],
    )

    return (
        starknet.state,
        owner_account,
        user1_account,
        user2_account,
        user3_account,
        zk_pad_token,
        zk_pad_vesting
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init):
    account_def, zk_pad_token_def, vesting_def = contract_defs
    state, owner_account, user1_account, user2_account, user3_account, zk_pad_token, zk_pad_vesting = contracts_init
    _state = state.copy()
    token = cached_contract(_state, zk_pad_token_def, zk_pad_token)
    vesting = cached_contract(_state, vesting_def, zk_pad_vesting)
    owner_cached = cached_contract(_state, account_def, owner_account)
    user1_cached = cached_contract(_state, account_def, user1_account)
    user2_cached = cached_contract(_state, account_def, user2_account)
    user3_cached = cached_contract(_state, account_def, user3_account)
    return _state, token, vesting, owner_cached, user1_cached, user2_cached, user3_cached


@pytest.mark.asyncio
async def test_reject_payee_zero_address(contract_defs, contracts_factory):
    account_def, zk_pad_token_def, vesting_def = contract_defs
    _state, token, vesting, owner, user1, user2, user3 = contracts_factory
    starknet = Starknet(_state)

    _start_timestamp = get_block_timestamp(starknet.state) + 3600

    zk_pad_vesting = assert_revert(starknet.deploy(
        contract_class=vesting_def,
        constructor_calldata=[
            vesting_len, [user1.contract_address,
                          "0x000000000000000000000000000000000000000000000000000000000"], vesting_len, shares,
            _start_timestamp, duration_seconds, token.contract_address
        ],
    ), "ZkPadVesting::payee can't be null")
