import pytest
import pytest_asyncio
from datetime import datetime, timedelta
from random import randint
from pprint import pprint as pp
from typing import Tuple

from signers import MockSigner
from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash
from starkware.starknet.business_logic.transaction.objects import TransactionExecutionInfo

from utils import *
from nile.signer import Signer

TRUE = 1
FALSE = 0
RND_NBR_GEN_SEED = 76823
ONE_DAY = 24 * 60 * 60

account_path = "openzeppelin/account/presets/Account.cairo"
ido_factory_path = "IDO/AstralyIDOFactory.cairo"
ido_path = "mocks/AstralyINOContract_mock.cairo"
rnd_nbr_gen_path = "utils/xoroshiro128_starstar.cairo"
erc20_eth_path = "mocks/Astraly_ETH_ERC20_mock.cairo"
erc721_path = "mocks/Astraly_ERC721_mock.cairo"

deployer = MockSigner(1234321)
admin1 = MockSigner(2345432)
staking = MockSigner(3456543)
sale_owner = MockSigner(4567654)
sale_participant = MockSigner(5678765)
sale_participant_2 = MockSigner(678909876)

sig_exp = 3000000000

PARTICIPATION_AMOUNT = to_uint(300 * 10**18)
MAX_PARTICIPATION = to_uint(5)
PARTICIPATION_VALUE = to_uint(100 * 10**18)

TOKEN_PRICE = to_uint(100 * 10**18)
TOKENS_TO_SELL = to_uint(50)

ADMIN_CUT = to_uint(0)


@pytest.fixture(scope="module")
def contract_defs():
    account_def = get_contract_def(account_path)
    refferal_def = get_contract_def(refferal_path)

    return (
        account_def,
        refferal_def,
    )


@pytest_asyncio.fixture(scope="module")
async def contracts_init(contract_defs, get_starknet):
    starknet = get_starknet
    (
        account_def,
        refferal_def
    ) = contract_defs
    await starknet.declare(contract_class=account_def)
    deployer_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[deployer.public_key]
    )
    admin1_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[admin1.public_key]
    )

    await starknet.declare(contract_class=refferal_def)
    refferal = await starknet.deploy(
        contract_class=refferal_def,
        constructor_calldata=[],
    )

    return (
        deployer_account,
        admin1_account,
        refferal
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init, get_starknet):
    (
        account_def,
        refferal_def
    ) = contract_defs
    (
        deployer_account,
        admin1_account,
        refferal
    ) = contracts_init
    _state = get_starknet.state.copy()
    deployer_cached = cached_contract(_state, account_def, deployer_account)
    admin1_cached = cached_contract(_state, account_def, admin1_account)
    referral_cached = cached_contract(_state, refferal_def, refferal)

    return (
        deployer_cached,
        admin1_cached,
        referral_cached,
        _state,
    )
