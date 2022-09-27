import pytest
import pytest_asyncio

from signers import MockSigner
from utils import *
import asyncio
from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash

from datetime import datetime, timedelta
from utils import get_block_timestamp, set_block_timestamp
from pprint import pprint as pp
from typing import Tuple

TRUE = 1
FALSE = 0
RND_NBR_GEN_SEED = 76823
ONE_DAY = 24 * 60 * 60

account_path = 'openzeppelin/account/presets/Account.cairo'
ido_factory_path = 'AstralyIDOFactory.cairo'
ido_path = 'AstralyIDOContract.cairo'
rnd_nbr_gen_path = 'utils/xoroshiro128_starstar.cairo'
erc20_eth_path = 'mocks/Astraly_ETH_ERC20_mock.cairo'

deployer = MockSigner(1234321)
admin1 = MockSigner(2345432)
staking = MockSigner(3456543)
sale_owner = MockSigner(4567654)
sale_participant = MockSigner(5678765)
sale_participant_2 = MockSigner(678909876)

sig_exp = 3000000000


def advance_clock(starknet_state, num_seconds):
    set_block_timestamp(
        starknet_state, get_block_timestamp(
            starknet_state) + num_seconds
    )


def days_to_seconds(days: int):
    return days * 24 * 60 * 60

    # function generateSignature(digest, privateKey) {
    # // prefix with "\x19Ethereum Signed Message:\n32"
    # // Reference: https: // github.com/OpenZeppelin/openzeppelin-contracts/issues/890
    # const prefixedHash = ethUtil.hashPersonalMessage(ethUtil.toBuffer(digest));

    # // sign message
    # const {v, r, s} = ethUtil.ecsign(prefixedHash, Buffer.from (privateKey, 'hex'))

    # // generate signature by concatenating r(32), s(32), v(1) in this order
    # // Reference: https: // github.com/OpenZeppelin/openzeppelin-contracts/blob/76fe1548aee183dfcc395364f0745fe153a56141/contracts/ECRecovery.sol  # L39-L43
    # const vb = Buffer.from ([v]);
    # const signature = Buffer.concat([r, s, vb]);

    # return signature; }


def generate_signature(digest, pk) -> Tuple[int, int]:
    # signer = Signer(pk)

    return admin1.signer.sign(message_hash=digest)

#   function signRegistration(signatureExpirationTimestamp, userAddress, roundId, contractAddress, privateKey) {
#     // compute keccak256(abi.encodePacked(user, roundId, address(this)))
#     const digest = ethers.utils.keccak256(
#       ethers.utils.solidityPack(
#         ['uint256', 'address', 'uint256', 'address'],
#         [signatureExpirationTimestamp, userAddress, roundId, contractAddress]
#       )
#     );

#     return generateSignature(digest, privateKey);
#   }


def sign_registration(signature_expiration_timestamp, user_address, contract_address, pk):
    digest = pedersen_hash(pedersen_hash(
        signature_expiration_timestamp, user_address), contract_address)

    return generate_signature(digest, pk)


@pytest_asyncio.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    set_block_timestamp(starknet.state, int(
        datetime.today().timestamp()))  # time.time()
    return starknet


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def(account_path)
    zk_pad_ido_factory_def = get_contract_def(ido_factory_path)
    rnd_nbr_gen_def = get_contract_def(rnd_nbr_gen_path)
    zk_pad_ido_def = get_contract_def(ido_path)
    erc20_eth_def = get_contract_def(erc20_eth_path)

    return account_def, zk_pad_ido_factory_def, rnd_nbr_gen_def, zk_pad_ido_def, erc20_eth_def


@pytest_asyncio.fixture(scope='module')
async def contracts_init(contract_defs, get_starknet):
    starknet = get_starknet
    account_def, zk_pad_ido_factory_def, rnd_nbr_gen_def, zk_pad_ido_def, erc20_eth_def = contract_defs
    await starknet.declare(contract_class=account_def)
    deployer_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[deployer.public_key]
    )
    admin1_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[admin1.public_key]
    )

    staking_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[staking.public_key]
    )
    sale_owner_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[sale_owner.public_key]
    )

    sale_participant_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[sale_participant.public_key]
    )

    sale_participant_2_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[sale_participant_2.public_key]
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
        constructor_calldata=[ido_class.class_hash,
                              deployer_account.contract_address],
    )

    await deployer.send_transaction(
        deployer_account, zk_pad_ido_factory.contract_address, 'set_random_number_generator_address',
        [rnd_nbr_gen.contract_address]
    )

    tx = (await deployer.send_transaction(deployer_account, zk_pad_ido_factory.contract_address, "create_ido",
                                          [admin1_account.contract_address]))
    ido_address = tx.call_info.internal_calls[0].events[0].data[1]

    ido = StarknetContract(starknet, zk_pad_ido_def.abi, ido_address, None)

    await starknet.declare(contract_class=erc20_eth_def)

    erc20_eth_token = await starknet.deploy(
        contract_class=erc20_eth_def,
        constructor_calldata=[
            deployer_account.contract_address,
            deployer_account.contract_address
        ],
    )

    await deployer.send_transaction(deployer_account, erc20_eth_token.contract_address, "transfer",
                                    [sale_participant_account.contract_address,
                                     *to_uint(10000)]
                                    )

    await deployer.send_transaction(deployer_account, erc20_eth_token.contract_address, "transfer",
                                    [sale_participant_2_account.contract_address,
                                     *to_uint(5000)]
                                    )

    await deployer.send_transaction(deployer_account, erc20_eth_token.contract_address, "transfer",
                                    [sale_owner_account.contract_address,
                                     *to_uint(1000000)]
                                    )

    await deployer.send_transaction(
        deployer_account,
        zk_pad_ido_factory.contract_address,
        "set_payment_token_address",
        [erc20_eth_token.contract_address])

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
        erc20_eth_token
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init, get_starknet):
    account_def, zk_pad_ido_factory_def, rnd_nbr_gen_def, zk_pad_ido_def, erc20_eth_def = contract_defs
    deployer_account, admin1_account, staking_account, sale_owner_account, sale_participant_account, sale_participant_2_account, rnd_nbr_gen, zk_pad_ido_factory, ido, erc20_eth_token = contracts_init
    _state = get_starknet.state.copy()
    deployer_cached = cached_contract(_state, account_def, deployer_account)
    admin1_cached = cached_contract(_state, account_def, admin1_account)
    staking_cached = cached_contract(_state, account_def, staking_account)
    owner_cached = cached_contract(_state, account_def, sale_owner_account)
    participant_cached = cached_contract(
        _state, account_def, sale_participant_account)
    participant_2_cached = cached_contract(
        _state, account_def, sale_participant_2_account)
    rnd_nbr_gen_cached = cached_contract(_state, rnd_nbr_gen_def, rnd_nbr_gen)
    ido_factory_cached = cached_contract(
        _state, zk_pad_ido_factory_def, zk_pad_ido_factory)
    ido_cached = cached_contract(_state, zk_pad_ido_def, ido)
    erc20_eth_token_cached = cached_contract(
        _state, erc20_eth_def, erc20_eth_token)
    return deployer_cached, admin1_cached, staking_cached, owner_cached, participant_cached, participant_2_cached, rnd_nbr_gen_cached, ido_factory_cached, ido_cached, erc20_eth_token_cached, _state

#########################
# SALE SETUP
#########################


@pytest_asyncio.fixture
async def setup_sale(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
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
            erc20_eth_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            *to_uint(1000)  # portion vesting precision
        ]
    )

    # SET REGISTRATION ROUND PARAMS

    reg_start = day + timeDeltaOneDay
    reg_end = reg_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_registration_time",
        [
            int(reg_start.timestamp()),
            int(reg_end.timestamp())
        ]
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
            *to_uint(500)
        ]
    )

    # DEPOSIT TOKENS
    await sale_owner.send_transaction(owner, erc20_eth_token.contract_address, 'approve', [ido.contract_address, *to_uint(1000000)])
    tx = await sale_owner.send_transaction(owner, ido.contract_address, 'deposit_tokens', [])


@pytest.mark.asyncio
async def test_setup_sale_success_with_events(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
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
            erc20_eth_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            *to_uint(1000)  # portion vesting precision
        ]
    )

    assert_event_emitted(tx, ido.contract_address, "sale_created", data=[
        owner.contract_address,
        *to_uint(100),
        *to_uint(1000000),
        int(sale_end.timestamp()),
        int(token_unlock.timestamp())
    ], order=2)

    VESTING_PERCENTAGES = uint_array([100, 200, 300, 400])

    VESTING_TIMES_UNLOCKED = [
        int(token_unlock.timestamp()) + (1 * 24 * 60 * 60),
        int(token_unlock.timestamp()) + (8 * 24 * 60 * 60),
        int(token_unlock.timestamp()) + (15 * 24 * 60 * 60),
        int(token_unlock.timestamp()) + (22 * 24 * 60 * 60)
    ]
    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_vesting_params",
        [
            4,
            *VESTING_TIMES_UNLOCKED,
            *uarr2cd(VESTING_PERCENTAGES),
            0
        ]
    )

    number_of_portions = await ido.get_number_of_vesting_portions().call()
    assert number_of_portions.result.res == 4

    portion_1 = await ido.get_vesting_portion_percent(1).call()
    assert portion_1.result.res == uint(100)

    portion_2 = await ido.get_vesting_portion_percent(2).call()
    assert portion_2.result.res == uint(200)

    portion_3 = await ido.get_vesting_portion_percent(3).call()
    assert portion_3.result.res == uint(300)

    portion_4 = await ido.get_vesting_portion_percent(4).call()
    assert portion_4.result.res == uint(400)

    reg_start = day + timeDeltaOneDay
    reg_end = reg_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_registration_time",
        [
            int(reg_start.timestamp()),
            int(reg_end.timestamp())
        ]
    )

    assert_event_emitted(tx, ido.contract_address, "registration_time_set", data=[
        int(reg_start.timestamp()),
        int(reg_end.timestamp())
    ])

    purchase_round_start = reg_end + timeDeltaOneDay
    purchase_round_end = purchase_round_start + timeDeltaOneWeek

    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_purchase_round_params",
        [
            int(purchase_round_start.timestamp()),
            int(purchase_round_end.timestamp()),
            *to_uint(500)
        ]
    )

    assert_event_emitted(tx, ido.contract_address, "purchase_round_set", data=[
        int(purchase_round_start.timestamp()),
        int(purchase_round_end.timestamp()),
        *to_uint(500)
    ])


@pytest.mark.asyncio
async def test_only_admin_can_setup_sale(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(sale_participant.send_transaction(
        participant,
        ido.contract_address,
        "set_sale_params",
        [
            erc20_eth_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AccessControl: caller is missing role')


@pytest.mark.asyncio
async def test_can_only_create_sale_once(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
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
            erc20_eth_token.contract_address,
            owner.contract_address,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            *to_uint(1000)  # portion vesting precision
        ]
    )

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), "AstralyIDOContract::set_sale_params Sale is already created")


@pytest.mark.asyncio
async def test_fail_setup_sale_zero_address(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_sale_params",
        [
            erc20_eth_token.contract_address,
            0,
            *to_uint(100),  # token price
            *to_uint(1000000),  # amount of tokens to sell
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params Sale owner address can not be 0')


@pytest.mark.asyncio
async def test_fail_setup_token_zero_address(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params Token address can not be 0')


@pytest.mark.asyncio
async def test_fail_setup_token_price_zero(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params IDO Token price must be greater than zero')


@pytest.mark.asyncio
async def test_fail_setup_tokens_sold_zero(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day + timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params Number of IDO Tokens to sell must be greater than zero')


@pytest.mark.asyncio
async def test_fail_setup_bad_timestamps(contracts_factory):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory
    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    sale_end = day - timeDelta90days
    token_unlock = sale_end + timeDeltaOneWeek

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params Sale end time in the past')

    sale_end = day + timeDelta90days
    token_unlock = day - timeDeltaOneDay

    await assert_revert(admin1.send_transaction(
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
            *to_uint(1000)  # portion vesting precision
        ]
    ), reverted_with='AstralyIDOContract::set_sale_params Tokens unlock time in the past')

#########################
# REGISTRATION
#########################


@pytest.mark.asyncio
async def test_registration_works(contracts_factory, setup_sale):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory

    # Check there are no registrants
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, 1234321)

    day = datetime.today()
    timeDelta90days = timedelta(days=90)
    timeDeltaOneWeek = timedelta(weeks=1)
    timeDeltaOneDay = timedelta(days=1)

    # Go to registration round start
    set_block_timestamp(starknet_state, int(
        (day + timeDeltaOneDay).timestamp()))

    await sale_participant.send_transaction(participant, ido.contract_address, 'register_user', [len(sig), *sig, sig_exp])

    tx = await ido.get_registration().call()
    # Check registrant counter has been incremented
    assert tx.result.res.number_of_registrants == uint(1)


@pytest.mark.asyncio
async def test_registration_fails_after_registration_ends(contracts_factory, setup_sale):
    deployer_account, admin_user, stakin_contract, owner, participant, participant_2, rnd_nbr_gen, ido_factory, ido, erc20_eth_token, starknet_state = contracts_factory

    # Check there are no registrants
    tx = await ido.get_registration().call()
    assert tx.result.res.number_of_registrants == uint(0)

    sig = sign_registration(
        sig_exp, participant.contract_address, ido.contract_address, 1234321)

    day = datetime.today()
    timeDelta8Days = timedelta(days=8)

    # Go to AFTER registration round end
    set_block_timestamp(starknet_state, int(
        (day + timeDelta8Days).timestamp()))

    await assert_revert(sale_participant.send_transaction(participant, ido.contract_address, 'register_user', [len(sig), *sig, sig_exp]), reverted_with='AstralyIDOContract::register_user Registration window is closed')
