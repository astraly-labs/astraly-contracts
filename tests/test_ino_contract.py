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
PARTICIPATION_VALUE = to_uint(200 * 10**18)

TOKEN_PRICE = to_uint(100 * 10**18)
TOKENS_TO_SELL = to_uint(50)


def generate_signature(digest, signer: Signer) -> Tuple[int, int]:
    return signer.sign(message_hash=digest)


def sign_registration(
    signature_expiration_timestamp, user_address, contract_address, signer: Signer
):
    digest = pedersen_hash(
        pedersen_hash(signature_expiration_timestamp,
                      user_address), contract_address
    )

    return generate_signature(digest, signer)


@pytest.fixture(scope="module")
def contract_defs():
    account_def = get_contract_def(account_path)
    zk_pad_ido_factory_def = get_contract_def(ido_factory_path)
    rnd_nbr_gen_def = get_contract_def(rnd_nbr_gen_path)
    zk_pad_ido_def = get_contract_def(ido_path)
    erc20_eth_def = get_contract_def(erc20_eth_path)
    erc721_def = get_contract_def(erc721_path)

    return (
        account_def,
        zk_pad_ido_factory_def,
        rnd_nbr_gen_def,
        zk_pad_ido_def,
        erc20_eth_def,
        erc721_def,
    )


@pytest_asyncio.fixture(scope="module")
async def contracts_init(contract_defs, get_starknet):
    starknet = get_starknet
    (
        account_def,
        zk_pad_ido_factory_def,
        rnd_nbr_gen_def,
        zk_pad_ido_def,
        erc20_eth_def,
        erc721_def,
    ) = contract_defs
    await starknet.declare(contract_class=account_def)
    deployer_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[deployer.public_key]
    )
    admin1_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[admin1.public_key]
    )

    staking_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[staking.public_key]
    )
    sale_owner_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[
            sale_owner.public_key]
    )

    sale_participant_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[
            sale_participant.public_key]
    )

    sale_participant_2_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[
            sale_participant_2.public_key]
    )

    await starknet.declare(contract_class=rnd_nbr_gen_def)
    rnd_nbr_gen = await starknet.deploy(
        contract_class=rnd_nbr_gen_def,
        constructor_calldata=[RND_NBR_GEN_SEED],
    )

    ido_class = await starknet.declare(contract_class=zk_pad_ido_def)
    await starknet.declare(contract_class=zk_pad_ido_factory_def)
    zk_pad_ido_factory = await starknet.deploy(
        contract_class=zk_pad_ido_factory_def,
        constructor_calldata=[deployer_account.contract_address],
    )

    await deployer.send_transaction(
        deployer_account,
        zk_pad_ido_factory.contract_address,
        "set_ino_contract_class_hash",
        [ido_class.class_hash],
    )

    await deployer.send_transaction(
        deployer_account,
        zk_pad_ido_factory.contract_address,
        "set_random_number_generator_address",
        [rnd_nbr_gen.contract_address],
    )

    tx = await deployer.send_transaction(
        deployer_account,
        zk_pad_ido_factory.contract_address,
        "create_ino",
        [admin1_account.contract_address, 0],
    )
    ido_address = tx.call_info.internal_calls[0].events[0].data[1]

    ido = StarknetContract(starknet, zk_pad_ido_def.abi, ido_address, None)

    await starknet.declare(contract_class=erc20_eth_def)

    erc20_eth_token = await starknet.deploy(
        contract_class=erc20_eth_def,
        constructor_calldata=[
            deployer_account.contract_address,
            deployer_account.contract_address,
        ],
    )

    await starknet.declare(contract_class=erc721_def)

    erc721_token = await starknet.deploy(
        contract_class=erc721_def,
        constructor_calldata=[
            deployer_account.contract_address,
        ],
    )

    await deployer.send_transaction(
        deployer_account,
        erc20_eth_token.contract_address,
        "transfer",
        [sale_participant_account.contract_address, *to_uint(50000 * 10**18)],
    )

    await deployer.send_transaction(
        deployer_account,
        erc20_eth_token.contract_address,
        "transfer",
        [sale_participant_2_account.contract_address,
            *to_uint(50000 * 10**18)],
    )

    await deployer.send_transaction(
        deployer_account,
        erc20_eth_token.contract_address,
        "transfer",
        [sale_owner_account.contract_address, *TOKENS_TO_SELL],
    )

    await deployer.send_transaction(
        deployer_account,
        zk_pad_ido_factory.contract_address,
        "set_payment_token_address",
        [erc20_eth_token.contract_address],
    )

    return (
        deployer_account,
        admin1_account,
        staking_account,
        sale_owner_account,
        sale_participant_account,
        sale_participant_2_account,
        rnd_nbr_gen,
        zk_pad_ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init, get_starknet):
    (
        account_def,
        zk_pad_ido_factory_def,
        rnd_nbr_gen_def,
        zk_pad_ido_def,
        erc20_eth_def,
        erc721_def,
    ) = contract_defs
    (
        deployer_account,
        admin1_account,
        staking_account,
        sale_owner_account,
        sale_participant_account,
        sale_participant_2_account,
        rnd_nbr_gen,
        zk_pad_ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
    ) = contracts_init
    _state = get_starknet.state.copy()
    deployer_cached = cached_contract(_state, account_def, deployer_account)
    admin1_cached = cached_contract(_state, account_def, admin1_account)
    staking_cached = cached_contract(_state, account_def, staking_account)
    owner_cached = cached_contract(_state, account_def, sale_owner_account)
    participant_cached = cached_contract(
        _state, account_def, sale_participant_account)
    participant_2_cached = cached_contract(
        _state, account_def, sale_participant_2_account
    )
    rnd_nbr_gen_cached = cached_contract(_state, rnd_nbr_gen_def, rnd_nbr_gen)
    ido_factory_cached = cached_contract(
        _state, zk_pad_ido_factory_def, zk_pad_ido_factory
    )
    ido_cached = cached_contract(_state, zk_pad_ido_def, ido)
    erc20_eth_token_cached = cached_contract(
        _state, erc20_eth_def, erc20_eth_token)
    erc721_token_cached = cached_contract(_state, erc721_def, erc721_token)
    return (
        deployer_cached,
        admin1_cached,
        staking_cached,
        owner_cached,
        participant_cached,
        participant_2_cached,
        rnd_nbr_gen_cached,
        ido_factory_cached,
        ido_cached,
        erc20_eth_token_cached,
        erc721_token_cached,
        _state,
    )


#########################
# SALE SETUP
#########################


@pytest_asyncio.fixture
async def setup_sale(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    # SET SALE PARAMS

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_sale_params",
        [
            erc721_token.contract_address,
            owner.contract_address,
            *TOKEN_PRICE,  # token price
            *TOKENS_TO_SELL,  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
        ],
    )

    # SET REGISTRATION ROUND PARAMS

    reg_start = day + timeDeltaOneDay
    reg_end = reg_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_registration_time",
        [int(reg_start.timestamp()), int(reg_end.timestamp())],
    )

    # SET PURCHASE ROUND PARAMS

    purchase_round_start = reg_end + timeDeltaOneDay
    purchase_round_end = purchase_round_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_purchase_round_params",
        [
            int(purchase_round_start.timestamp()),
            int(purchase_round_end.timestamp()),
            *MAX_PARTICIPATION,
        ],
    )


@pytest.mark.asyncio
async def test_setup_sale_success_with_events(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_sale_params",
        [
            erc721_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
        ],
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "SaleCreated",
        data=[
            owner.contract_address,
            *to_uint(100),
            *to_uint(1000000),
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
        ],
    )

    reg_start = day + timeDeltaOneDay
    reg_end = reg_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_registration_time",
        [int(reg_start.timestamp()), int(reg_end.timestamp())],
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "RegistrationTimeSet",
        data=[int(reg_start.timestamp()), int(reg_end.timestamp())],
    )

    purchase_round_start = reg_end + timeDeltaOneDay
    purchase_round_end = purchase_round_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_purchase_round_params",
        [
            int(purchase_round_start.timestamp()),
            int(purchase_round_end.timestamp()),
            *to_uint(500),
        ],
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "PurchaseRoundSet",
        data=[
            int(purchase_round_start.timestamp()),
            int(purchase_round_end.timestamp()),
            *to_uint(500),
        ],
    )


@pytest.mark.asyncio
async def test_only_admin_can_setup_sale(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "set_sale_params",
            [
                erc721_token.contract_address,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with=f"AccessControl::Caller is missing role {str_to_felt('OWNER')}",
    )


@pytest.mark.asyncio
async def test_can_only_create_sale_once(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_sale_params",
        [
            erc721_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
        ],
    )

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc721_token.contract_address,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        "set_sale_params::Sale is already created",
    )


@pytest.mark.asyncio
async def test_fail_setup_sale_zero_address(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc721_token.contract_address,
                0,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::Sale owner address can not be 0",
    )


@pytest.mark.asyncio
async def test_fail_setup_token_zero_address(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                0,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::Token address can not be 0",
    )


@pytest.mark.asyncio
async def test_fail_setup_token_price_zero(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc20_eth_token.contract_address,
                owner.contract_address,
                *to_uint(0),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::IDO Token price must be greater than zero",
    )


@pytest.mark.asyncio
async def test_fail_setup_tokens_sold_zero(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc20_eth_token.contract_address,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(0),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::Number of IDO Tokens to sell must be greater than zero",
    )


@pytest.mark.asyncio
async def test_fail_setup_bad_timestamps(contracts_factory):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day - timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc20_eth_token.contract_address,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::Sale end time in the past",
    )

    sale_end = day + timeDelta90days
    token_unlock = day - timeDeltaOneDay

    await assert_revert(
        admin1.send_transaction(
            admin_user,
            ido.contract_address,
            "set_sale_params",
            [
                erc20_eth_token.contract_address,
                owner.contract_address,
                *to_uint(100),  # token price
                *to_uint(1000000),  # amount of tokens to sell
                int(sale_end.timestamp()),
                int(token_unlock.timestamp()),
            ],
        ),
        reverted_with="set_sale_params::Tokens unlock time in the past",
    )


#########################
# REGISTRATION
#########################


@pytest.mark.asyncio
async def test_registration_works(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    # Check there are no registrants
    current_sale = (await ido.get_current_sale().call()).result.res
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    day = datetime.today()
    time_delta_one_day = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + time_delta_one_day).timestamp()))

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    await deployer.send_transaction(
        deployer_account,
        rnd_nbr_gen.contract_address,
        "update_seed",
        [randint(1, 9999999999999999999)],
    )

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    assert_event_emitted(
        tx, ido.contract_address, "UserRegistered", [
            participant.contract_address]
    )

    current_registration = (await ido.get_registration().call()).result.res
    # Check registrant counter has been incremented
    assert current_registration.number_of_registrants == uint(1)

    users_list_len = 200
    users_addresses = list()
    users_score = list()
    for x in range(users_list_len):
        users_addresses.append(randint(99999, 9999999999999))
        users_score.append(randint(1, 100))

    await deployer.send_transaction(
        deployer_account,
        ido.contract_address,
        "register_users",
        [
            len(users_addresses),
            *list(users_addresses),
            len(users_score),
            *list(users_score),
        ],
    )

    set_block_timestamp(
        starknet_state, current_registration.registration_time_ends + 1)

    # Check the winners array integrity
    winners_arr = (await ido.get_winners().call()).result.arr
    print(winners_arr)
    winners_arr.sort()
    for winner in set(winners_arr):
        allocation = from_uint((await ido.get_allocation(winner).call()).result.res)
        assert allocation == winners_arr.count(winner)


@pytest.mark.asyncio
async def test_registration_fails_bad_timestamps(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    # Check there are no registrants
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta8Days = timedelta(days=8)
    timeDelta1Days = timedelta(days=1)

    # Go to AFTER registration round end
    set_block_timestamp(starknet_state, int(
        (day + timeDelta8Days).timestamp()))

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "register_user",
            [len(sig), *sig, sig_exp],
        ),
        reverted_with="register_user::Registration window is closed",
    )
    # Go to BEFORE registration round start
    set_block_timestamp(starknet_state, int(
        (day - timeDelta1Days).timestamp()))

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "register_user",
            [len(sig), *sig, sig_exp],
        ),
        reverted_with="register_user::Registration window is closed",
    )


@pytest.mark.asyncio
async def test_registration_fails_signature_invalid(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    # Check there are no registrants
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    sig = sign_registration(
        sig_exp, participant_2.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "register_user",
            [len(sig), *sig, sig_exp],
        ),
        reverted_with="register_user::Invalid signature",
    )


@pytest.mark.asyncio
async def test_registration_fails_register_twice(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    # Check there are no registrants
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "register_user",
            [len(sig), *sig, sig_exp],
        ),
        reverted_with="register_user::User already registered",
    )


#########################
# PARTICIPATION
#########################


@pytest.mark.asyncio
async def test_participation_works(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    tx = await sale_participant.send_transaction(
        participant,
        ido.contract_address,
        "participate",
        [*PARTICIPATION_VALUE],
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "TokensSold",
        [participant.contract_address, *to_uint(2)],
        order=2,
    )

    tx = await ido.get_user_info(participant.contract_address).call()
    pp(tx.result)

    assert tx.result.has_participated is True
    assert tx.result.participation.amount_bought == to_uint(2)
    assert tx.result.participation.amount_paid == PARTICIPATION_VALUE

    tx = await ido.get_current_sale().call()

    assert tx.result.res.number_of_participants == to_uint(1)
    assert tx.result.res.total_tokens_sold == to_uint(2)
    assert tx.result.res.total_raised == PARTICIPATION_VALUE


@pytest.mark.asyncio
async def test_participation_double(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )
    sig2 = sign_registration(
        sig_exp, participant_2.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )
    tx = await sale_participant_2.send_transaction(
        participant_2,
        ido.contract_address,
        "register_user",
        [len(sig2), *sig2, sig_exp],
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    tx = await sale_participant.send_transaction(
        participant,
        ido.contract_address,
        "participate",
        [*PARTICIPATION_VALUE],
    )

    await sale_participant_2.send_transaction(
        participant_2,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )

    tx = await sale_participant_2.send_transaction(
        participant_2,
        ido.contract_address,
        "participate",
        [*PARTICIPATION_VALUE],
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "TokensSold",
        [participant_2.contract_address, *to_uint(2)],
        order=2,
    )

    tx = await ido.get_user_info(participant.contract_address).call()
    assert tx.result.has_participated == True
    assert tx.result.participation.amount_bought == to_uint(2)
    assert tx.result.participation.amount_paid == PARTICIPATION_VALUE

    tx = await ido.get_user_info(participant_2.contract_address).call()
    assert tx.result.has_participated == True
    assert tx.result.participation.amount_bought == to_uint(2)
    assert tx.result.participation.amount_paid == PARTICIPATION_VALUE

    tx = await ido.get_current_sale().call()

    assert tx.result.res.number_of_participants == to_uint(2)
    assert tx.result.res.total_tokens_sold == to_uint(4)
    assert tx.result.res.total_raised == to_uint(400 * 10**18)


@pytest.mark.skip
@pytest.mark.asyncio
async def test_participation_fails_max_participation(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    INVALID_PARTICIPATION_AMOUNT = to_uint(501 * 10**18)

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*PARTICIPATION_VALUE],
        ),
        reverted_with="participate::Crossing max participation",
    )


@pytest.mark.asyncio
async def test_participation_fails_twice(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    # When
    await sale_participant.send_transaction(
        participant,
        ido.contract_address,
        "participate",
        [*PARTICIPATION_VALUE],
    )

    # Then
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*PARTICIPATION_VALUE],
        ),
        reverted_with="participate::User participated",
    )


@pytest.mark.asyncio
async def test_participation_fails_bad_timestamps(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDelta45days = timedelta(days=45)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*PARTICIPATION_VALUE],
        ),
        reverted_with="participate::Purchase round has not started yet",
    )

    # Go to purchase round after end
    set_block_timestamp(starknet_state, int(
        (day + timeDelta45days).timestamp()))

    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*PARTICIPATION_VALUE],
        ),
        reverted_with="participate::Purchase round is over",
    )


@pytest.mark.asyncio
async def test_participation_fails_not_registered(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    # Omit registration
    # tx = await sale_participant.send_transaction(participant, ido.contract_address, 'register_user', [len(sig), *sig, sig_exp])

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    # Reverts as user is not registered
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*PARTICIPATION_VALUE],
        ),
        reverted_with="participate::No allocation",
    )


@pytest.mark.asyncio
async def test_participation_fails_0_tokens(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    # await sale_participant.send_transaction(participant, erc20_eth_token.contract_address, 'approve', [ido.contract_address, *PARTICIPATION_VALUE])
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*to_uint(0)],
        ),
        reverted_with="participate::Can't buy 0 tokens",
    )


@pytest.mark.asyncio
async def test_participation_fails_exceeds_allocation(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta10days = timedelta(days=10)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    # 50_005 / 100 = 500,05 > PARTICIPATION_AMOUNT
    INVALID_PARTICIPATION_VALUE = to_uint(50005 * 10**18)

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *INVALID_PARTICIPATION_VALUE],
    )
    await assert_revert(
        sale_participant.send_transaction(
            participant,
            ido.contract_address,
            "participate",
            [*INVALID_PARTICIPATION_VALUE],
        ),
        reverted_with="participate::Exceeding allowance",
    )


#########################
# WITHDRAW TOKENS
#########################


@pytest.mark.asyncio
async def test_withdraw_tokens(contracts_factory, setup_sale):
    (
        deployer_account,
        admin_user,
        stakin_contract,
        owner,
        participant,
        participant_2,
        rnd_nbr_gen,
        ido_factory,
        ido,
        erc20_eth_token,
        erc721_token,
        starknet_state,
    ) = contracts_factory

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, admin1.signer
    )

    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDelta10days = timedelta(days=10)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "register_user", [
            len(sig), *sig, sig_exp]
    )

    # Go to purchase round start
    set_block_timestamp(starknet_state, int(
        (day + timeDelta10days).timestamp()))

    await sale_participant.send_transaction(
        participant,
        erc20_eth_token.contract_address,
        "approve",
        [ido.contract_address, *PARTICIPATION_VALUE],
    )
    tx = await sale_participant.send_transaction(
        participant,
        ido.contract_address,
        "participate",
        [*PARTICIPATION_VALUE],
    )

    await assert_revert(
        sale_participant.send_transaction(
            participant, ido.contract_address, "withdraw_tokens", []
        ),
        reverted_with="withdraw_tokens::Tokens can not be withdrawn yet",
    )

    # Go to distribution round start
    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek
    # advance block time stamp to one minute after portion 1 vesting unlock time
    set_block_timestamp(
        starknet_state, int(token_unlock.timestamp()) + (1 * 24 * 60 * 60) + 60
    )

    balance_before = await erc721_token.balanceOf(participant.contract_address).call()
    tx = await sale_participant.send_transaction(
        participant, ido.contract_address, "withdraw_tokens", []
    )

    assert_event_emitted(
        tx,
        ido.contract_address,
        "TokensWithdrawn",
        [participant.contract_address, *to_uint(2)],
        order=1,
    )
    balance_after = await erc721_token.balanceOf(participant.contract_address).call()

    assert int(balance_after.result.balance[0]) == int(
        balance_before.result.balance[0]
    ) + int(PARTICIPATION_VALUE[0] / TOKEN_PRICE[0])
