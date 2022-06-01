import time
import asyncio
import pytest
from starkware.starknet.public.abi import get_selector_from_name

from utils import (
    Signer, to_uint, from_uint, str_to_felt, MAX_UINT256, get_contract_def, cached_contract, assert_revert,
    assert_event_emitted, get_block_timestamp, set_block_timestamp, get_block_number, set_block_number, assert_approx_eq
)
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starknet.testing.starknet import Starknet


def parse_ether(value: int):
    return int(value * 1e18)


INIT_SUPPLY = to_uint(parse_ether(1_000_000))
CAP = to_uint(parse_ether(1_000_000_000_000))
UINT_ONE = to_uint(1)
UINT_ZERO = to_uint(0)
NAME = str_to_felt("xZkPad")
SYMBOL = str_to_felt("xZKP")
DECIMALS = 18

REWARDS_PER_BLOCK = to_uint(parse_ether(10))
owner = Signer(1234)


def calculate_lock_time_bonus(shares: int, lock_time=365):
    return int((shares * lock_time) / 730)


def remove_lock_time_bonus(shares: int, lock_time=None):
    if lock_time is None:
        return int((shares * 730) / 365)
    return int((shares * 730) / lock_time)


def remove_lock_time_bonus_uint(shares, lock_time=None):
    if lock_time is None:
        return to_uint(int((from_uint(shares) * 730) / 365))
    return to_uint(int((from_uint(shares) * 730) / lock_time))


def advance_clock(starknet_state, num_seconds):
    set_block_timestamp(
        starknet_state, get_block_timestamp(
            starknet_state) + num_seconds
    )


def days_to_seconds(days: int):
    return days * 24 * 60 * 60


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    set_block_timestamp(starknet.state, int(time.time()))
    set_block_number(starknet.state, 0)
    return starknet


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def('openzeppelin/account/Account.cairo')
    proxy_def = get_contract_def('openzeppelin/upgrades/Proxy.cairo')
    zk_pad_token_def = get_contract_def('tests/mocks/test_ZkPadToken.cairo')
    zk_pad_stake_def = get_contract_def('ZkPadStaking.cairo')
    return account_def, proxy_def, zk_pad_token_def, zk_pad_stake_def


@pytest.fixture(scope='module')
async def contacts_init(contract_defs, get_starknet):
    starknet = get_starknet
    account_def, proxy_def, zk_pad_token_def, zk_pad_stake_def = contract_defs

    owner_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[owner.public_key]
    )

    zk_pad_token = await starknet.deploy(
        contract_def=zk_pad_token_def,
        constructor_calldata=[
            str_to_felt("ZkPad"),
            str_to_felt("ZKP"),
            DECIMALS,
            *INIT_SUPPLY,
            owner_account.contract_address,  # recipient
            owner_account.contract_address,  # owner
            *CAP,
            123124
        ],
    )

    zk_pad_stake_implementation = await starknet.deploy(contract_def=zk_pad_stake_def)

    zk_pad_stake_proxy = await starknet.deploy(contract_def=proxy_def,
                                               constructor_calldata=[zk_pad_stake_implementation.contract_address])

    START_BLOCK = get_block_number(starknet.state)
    END_BLOCK = START_BLOCK + 10_000

    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "initializer", [
        NAME,
        SYMBOL,
        zk_pad_token.contract_address,
        owner_account.contract_address,
        *REWARDS_PER_BLOCK,
        START_BLOCK,
        END_BLOCK
    ])

    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "setFeePercent", [int(0.1e18)])
    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "setHarvestDelay",
                                 [6 * 60 * 60])  # 6 hours
    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "setTargetFloatPercent",
                                 [int(0.1e18)])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "set_vault_address",
                                 [zk_pad_stake_proxy.contract_address])

    return (
        owner_account,
        zk_pad_token,
        zk_pad_stake_proxy
    )


@pytest.fixture
async def contracts_factory(contract_defs, contacts_init, get_starknet):
    account_def, proxy_def, zk_pad_token_def, zk_pad_stake_def = contract_defs
    owner_account, zk_pad_token, zk_pad_stake = contacts_init
    _state = get_starknet.state.copy()
    token = cached_contract(_state, zk_pad_token_def, zk_pad_token)
    stake = cached_contract(_state, zk_pad_stake_def, zk_pad_stake)
    owner_cached = cached_contract(_state, account_def, owner_account)

    async def deploy_contract_func(contract_name, constructor_calldata=None):
        contract_def = get_contract_def(contract_name)
        starknet = Starknet(_state)
        deployed_contract = await starknet.deploy(
            contract_def=contract_def,
            constructor_calldata=constructor_calldata)
        contract = cached_contract(_state, contract_def, deployed_contract)

        return contract

    async def deploy_account_func(public_key):
        starknet = Starknet(_state)
        deployed_account = await starknet.deploy(
            contract_def=account_def,
            constructor_calldata=[public_key]
        )
        cached_account = cached_contract(_state, account_def, deployed_account)
        return cached_account

    return token, stake, owner_cached, deploy_account_func, deploy_contract_func, _state


@pytest.mark.asyncio
@pytest.mark.order(1)
async def test_init(contracts_factory):
    zk_pad_token, zk_pad_staking, _, _, _, _ = contracts_factory
    assert (await zk_pad_staking.name().invoke()).result.name == NAME
    assert (await zk_pad_staking.symbol().invoke()).result.symbol == SYMBOL
    assert (await zk_pad_staking.decimals().invoke()).result.decimals == 18
    assert (await zk_pad_staking.asset().invoke()).result.assetTokenAddress == zk_pad_token.contract_address
    assert (await zk_pad_staking.totalAssets().invoke()).result.totalManagedAssets == UINT_ZERO


async def cache_on_state(state, contract_def, deployment_func):
    deployment = await deployment_func
    return cached_contract(state, contract_def, deployment)


@pytest.mark.asyncio
async def test_proxy_upgrade(contract_defs):
    account_def, proxy_def, _, zk_pad_stake_def = contract_defs
    erc20_def = get_contract_def('openzeppelin/token/erc20/ERC20.cairo')
    starknet = await Starknet.empty()
    user = Signer(123)
    owner_account = await cache_on_state(starknet.state, account_def, starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[owner.public_key]
    ))
    user_account = await cache_on_state(starknet.state, account_def, starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[user.public_key]
    ))

    erc20_contract = await cache_on_state(
        starknet.state, erc20_def, starknet.deploy(contract_def=erc20_def, constructor_calldata=[
            str_to_felt("ZkPad"),
            str_to_felt("ZKP"),
            DECIMALS,
            *INIT_SUPPLY,
            owner_account.contract_address
        ]))

    zk_pad_stake_implementation = await cache_on_state(
        starknet.state, zk_pad_stake_def, starknet.deploy(contract_def=zk_pad_stake_def))

    zk_pad_stake_proxy = await cache_on_state(starknet.state, zk_pad_stake_def, starknet.deploy(contract_def=proxy_def,
                                                                                                constructor_calldata=[
                                                                                                    zk_pad_stake_implementation.contract_address]))

    START_BLOCK = 0
    END_BLOCK = START_BLOCK + 10_000

    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "initializer", [
        NAME,
        SYMBOL,
        erc20_contract.contract_address,
        owner_account.contract_address,
        *REWARDS_PER_BLOCK,
        START_BLOCK,
        END_BLOCK
    ])

    current_zk_pad_stake_implementation_address = (
        await user.send_transaction(user_account, zk_pad_stake_proxy.contract_address, "getImplementation",
                                    [])).result.response[0]
    assert zk_pad_stake_implementation.contract_address == current_zk_pad_stake_implementation_address

    new_zk_pad_implementation = await cache_on_state(
        starknet.state, zk_pad_stake_def, starknet.deploy(contract_def=zk_pad_stake_def))
    await assert_revert(
        user.send_transaction(
            user_account, zk_pad_stake_proxy.contract_address, "upgrade",
            [new_zk_pad_implementation.contract_address]),
        "Proxy: caller is not admin",
        StarknetErrorCode.TRANSACTION_FAILED
    )
    await owner.send_transaction(owner_account, zk_pad_stake_proxy.contract_address, "upgrade",
                                 [new_zk_pad_implementation.contract_address])
    current_zk_pad_stake_implementation_address = (
        await user.send_transaction(user_account, zk_pad_stake_proxy.contract_address, "getImplementation",
                                    [])).result.response[0]
    assert new_zk_pad_implementation.contract_address == current_zk_pad_stake_implementation_address


@pytest.mark.asyncio
async def test_conversions(contract_defs, contracts_factory):
    _, zk_pad_staking, _, _, _, _ = contracts_factory
    shares = to_uint(1000)
    assets = to_uint(1000)

    # convertToAssets(convertToShares(assets)) == assets
    converted_shares = (await zk_pad_staking.convertToShares(assets).invoke()).result.shares
    converted_assets = (await zk_pad_staking.convertToAssets(converted_shares).invoke()).result.assets
    assert assets == converted_assets

    # convertToShares(convertToAssets(shares)) == shares
    converted_assets = (await zk_pad_staking.convertToAssets(shares).invoke()).result.assets
    converted_shares = (await zk_pad_staking.convertToShares(converted_assets).invoke()).result.shares
    assert shares == converted_shares


@pytest.mark.asyncio
async def test_deposit_redeem_flow(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, starknet_state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "mint",
        [user1_account.contract_address, *to_uint(100_000)],
    )
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)

    assert (
        await zk_pad_staking.maxDeposit(user1_account.contract_address).invoke()
    ).result.maxAssets == MAX_UINT256

    # max approve
    await user1.send_transaction(
        user1_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *MAX_UINT256],
    )

    amount = to_uint(10_000)
    expected_user_asset_balance = calculate_lock_time_bonus(10_000)

    # deposit asset tokens to the vault, get shares
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "deposit",
        [*amount, user1_account.contract_address],
    )
    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(expected_user_asset_balance)
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Deposit", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        *amount,
        *tx.result.response
    ])
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(90_000)

    advance_clock(starknet_state, days_to_seconds(365) + 1)
    # redeem vault shares, get back assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "redeem",
        [*to_uint(expected_user_asset_balance), user1_account.contract_address,
         user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Withdraw", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        user1_account.contract_address,
        *tx.result.response,
        *to_uint(expected_user_asset_balance),
    ])
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)


@pytest.mark.asyncio
async def test_deposit_for_time_and_redeem_flow(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, starknet_state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "mint",
        [user1_account.contract_address, *to_uint(100_000)],
    )
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)

    assert (
        await zk_pad_staking.maxDeposit(user1_account.contract_address).invoke()
    ).result.maxAssets == MAX_UINT256

    # max approve
    await user1.send_transaction(
        user1_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *MAX_UINT256],
    )

    amount = to_uint(10_000)
    deposit_days = 365 * 2
    expected_user_asset_balance = calculate_lock_time_bonus(
        10_000, deposit_days)
    current_timestamp = get_block_timestamp(starknet_state)

    # deposit asset tokens to the vault, get shares
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "depositForTime",
        [*amount, user1_account.contract_address, deposit_days],
    )
    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(expected_user_asset_balance)

    set_block_timestamp(
        starknet_state, current_timestamp + days_to_seconds(365 * 2) + 1)
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "redeem",
        [*to_uint(expected_user_asset_balance), user1_account.contract_address,
         user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Withdraw", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        user1_account.contract_address,
        *tx.result.response,
        *amount,
    ])
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)


@pytest.mark.asyncio
async def test_mint_withdraw_flow(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, starknet_state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "mint",
        [user1_account.contract_address, *to_uint(100_000)],
    )
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)

    assert (
        await zk_pad_staking.maxMint(user1_account.contract_address).invoke()
    ).result.maxShares == MAX_UINT256
    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == UINT_ZERO

    # max approve
    await user1.send_transaction(
        user1_account, zk_pad_token.contract_address, "approve", [
            zk_pad_staking.contract_address, *MAX_UINT256]
    )

    shares = to_uint(10_000)
    expected_user_asset_balance = remove_lock_time_bonus(10_000)
    # mint shares for assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "mint",
        [*shares, user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == shares
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Deposit", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        *to_uint(expected_user_asset_balance),
        *shares
    ])

    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000 - expected_user_asset_balance)
    advance_clock(starknet_state, days_to_seconds(365) + 1)
    # withdraw shares, get back assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(expected_user_asset_balance), user1_account.contract_address,
         user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == UINT_ZERO

    assert_event_emitted(tx, zk_pad_staking.contract_address, "Withdraw", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        user1_account.contract_address,
        *to_uint(expected_user_asset_balance),
        *tx.result.response,
    ])
    assert (
        await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(100_000)


@pytest.mark.asyncio
async def test_allowances(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, starknet_state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    user2 = Signer(3456)
    user2_account = await deploy_account_func(user2.public_key)

    user3 = Signer(4567)
    user3_account = await deploy_account_func(user3.public_key)

    amount = to_uint(100_000)

    # mint assets to user1
    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "mint",
        [user1_account.contract_address, *amount]
    )
    assert (await zk_pad_token.balanceOf(user1_account.contract_address).invoke()).result.balance == amount

    # have user1 get shares in vault
    await user1.send_transaction(
        user1_account, zk_pad_token.contract_address, "approve", [
            zk_pad_staking.contract_address, *MAX_UINT256]
    )
    expected_shares = (await zk_pad_staking.previewDeposit(amount).call()).result.shares
    tx = await user1.send_transaction(
        user1_account, zk_pad_staking.contract_address, "mint", [
            *expected_shares, user1_account.contract_address]
    )

    advance_clock(starknet_state, days_to_seconds(365) + 1)
    # max approve user2
    await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "approve",
        [user2_account.contract_address, *MAX_UINT256],
    )

    # approve user3 for 10K SHARES
    await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "approve",
        [user3_account.contract_address, *to_uint(10_000)],
    )

    #
    # have user2 withdraw 20K ASSETS from user1 vault position
    #
    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == expected_shares
    assert (
        await zk_pad_staking.balanceOf(user2_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert (
        await zk_pad_token.balanceOf(user2_account.contract_address).invoke()
    ).result.balance == UINT_ZERO

    await user2.send_transaction(
        user2_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(20_000), user2_account.contract_address,
         user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(40_000)
    assert (
        await zk_pad_staking.balanceOf(user2_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert (
        await zk_pad_token.balanceOf(user2_account.contract_address).invoke()
    ).result.balance == to_uint(20_000)
    assert (
        await zk_pad_staking.allowance(
            user1_account.contract_address, user2_account.contract_address
        ).invoke()
    ).result.remaining == MAX_UINT256

    #
    # have user3 withdraw 20K ASSETS from user1 vault position
    #
    assert (
        await zk_pad_staking.balanceOf(user3_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert (
        await zk_pad_token.balanceOf(user3_account.contract_address).invoke()
    ).result.balance == UINT_ZERO

    await user3.send_transaction(
        user3_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(20_000), user3_account.contract_address,
         user1_account.contract_address],
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(30_000)
    assert (
        await zk_pad_staking.balanceOf(user3_account.contract_address).invoke()
    ).result.balance == UINT_ZERO
    assert (
        await zk_pad_token.balanceOf(user3_account.contract_address).invoke()
    ).result.balance == to_uint(20_000)
    assert (
        await zk_pad_staking.allowance(
            user1_account.contract_address, user3_account.contract_address
        ).invoke()
    ).result.remaining == UINT_ZERO

    # user3 tries withdrawing again, has insufficient allowance, :burn:
    await assert_revert(user3.send_transaction(
        user3_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(10), user3_account.contract_address,
         user1_account.contract_address],
    ), error_code=StarknetErrorCode.TRANSACTION_FAILED)


@pytest.mark.asyncio
async def test_permissions(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, _ = contracts_factory
    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    await assert_revert(
        user1.send_transaction(
            user1_account, zk_pad_staking.contract_address, "addWhitelistedToken", [123, 123, False]),
        "Ownable: caller is not the owner")

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "addWhitelistedToken",
                                 [123, 123, False])

    await assert_revert(
        user1.send_transaction(
            user1_account, zk_pad_staking.contract_address, "removeWhitelistedToken", [123]),
        "Ownable: caller is not the owner")

    await assert_revert(user1.send_transaction(user1_account, zk_pad_staking.contract_address, "setStakeBoost", [25]))


@pytest.mark.asyncio
async def test_deposit_lp(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, deploy_contract_func, starknet_state = contracts_factory

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "updateRewardPerBlockAndEndBlock",
                                 [*UINT_ZERO, get_block_number(starknet_state) + 1])
    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    deposit_amount = 10_000
    boost_value = int(2.5 * 10)
    initial_lock_time = 365  # days

    mint_calculator = await deploy_contract_func("tests/mocks/test_mint_calculator.cairo")
    mock_lp_token = await deploy_contract_func("tests/mocks/test_erc20.cairo", [
        str_to_felt("ZKP ETH LP"),
        str_to_felt("ZKP/ETH"),
        DECIMALS,
        *to_uint(deposit_amount * 2),
        user1_account.contract_address,
        owner_account.contract_address
    ])

    # just to have balance for withdraw after earn interest
    await user1.send_transaction(
        user1_account,
        mock_lp_token.contract_address,
        "transfer",
        [zk_pad_staking.contract_address, *to_uint(deposit_amount)]
    )  # TODO: Remove after implementing the withdraw from investment strategies function

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "setStakeBoost", [boost_value])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "addWhitelistedToken", [
        mock_lp_token.contract_address,
        mint_calculator.contract_address,
        False
    ])

    assert (
        await zk_pad_staking.isTokenWhitelisted(mock_lp_token.contract_address).call()
    ).result.res == 1

    assert (
        await mock_lp_token.balanceOf(user1_account.contract_address).call()
    ).result.balance == to_uint(deposit_amount)
    zkp_assets_value = (
        await mint_calculator.getAmountToMint(to_uint(deposit_amount)).call()
    ).result.amount
    assert zkp_assets_value == to_uint(deposit_amount)  # mock tokens

    current_boost_value = (await zk_pad_staking.getCurrentBoostValue().call()).result.res
    assert boost_value == current_boost_value

    expect_to_mint = int(
        current_boost_value * calculate_lock_time_bonus(deposit_amount, initial_lock_time) / 10)
    preview_deposit = (
        await zk_pad_staking.previewDepositLP(mock_lp_token.contract_address, to_uint(deposit_amount),
                                              initial_lock_time).call()
    ).result.shares
    assert preview_deposit == to_uint(expect_to_mint)

    await user1.send_transaction(
        user1_account,
        mock_lp_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *to_uint(deposit_amount)]
    )

    vault_balance_before_deposit = (
        await mock_lp_token.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    timestamp = get_block_timestamp(starknet_state)

    await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "depositLP",
        [mock_lp_token.contract_address,
         *to_uint(deposit_amount), user1_account.contract_address, initial_lock_time]
    )
    user_xzkp_balance = (await zk_pad_staking.balanceOf(user1_account.contract_address).call()).result.balance
    assert user_xzkp_balance == to_uint(expect_to_mint)

    vault_balance_after_deposit = (await mock_lp_token.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert from_uint(vault_balance_after_deposit) == from_uint(
        vault_balance_before_deposit) + deposit_amount

    user_stake_info = (await zk_pad_staking.getUserStakeInfo(user1_account.contract_address).call()).result

    assert user_stake_info.unlock_time == timestamp + \
        days_to_seconds(initial_lock_time)
    assert mock_lp_token.contract_address in user_stake_info.tokens

    set_block_timestamp(starknet_state, user_stake_info.unlock_time + 1)

    vault_balance_before_redeem = (await mock_lp_token.balanceOf(zk_pad_staking.contract_address).call()).result.balance

    withdraw_tx = await user1.send_transaction(user1_account, zk_pad_staking.contract_address, "withdrawLP", [
        mock_lp_token.contract_address, *
        to_uint(deposit_amount), user1_account.contract_address,
        user1_account.contract_address])

    vault_balance_after_redeem = (await mock_lp_token.balanceOf(zk_pad_staking.contract_address).call()).result.balance

    assert from_uint(vault_balance_before_redeem) == from_uint(
        vault_balance_after_redeem) + deposit_amount

    assert_event_emitted(withdraw_tx, zk_pad_staking.contract_address, "WithdrawLP", [
        user1_account.contract_address,
        user1_account.contract_address,
        user1_account.contract_address,
        mock_lp_token.contract_address,
        *to_uint(deposit_amount),
        *to_uint(deposit_amount),
    ])

    assert (
        await mock_lp_token.balanceOf(user1_account.contract_address).call()
    ).result.balance == to_uint(deposit_amount)


@pytest.mark.asyncio
async def test_atomic_deposit_withdraw(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, _, _, starknet_state = contracts_factory
    decimals = (await zk_pad_staking.decimals().call()).result.decimals
    # max approve
    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *INIT_SUPPLY],
    )
    pre_deposit_bal = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*INIT_SUPPLY, owner_account.contract_address])
    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == INIT_SUPPLY
    assert (await zk_pad_staking.totalFloat().call()).result.float == INIT_SUPPLY
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(INIT_SUPPLY))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == INIT_SUPPLY
    user_token_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_token_balance) == from_uint(
        pre_deposit_bal) - from_uint(INIT_SUPPLY)

    set_block_timestamp(
        starknet_state, get_block_timestamp(starknet_state) + days_to_seconds(365) + 1)
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdraw",
                                 [*INIT_SUPPLY, owner_account.contract_address, owner_account.contract_address])
    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == UINT_ZERO
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == 0
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == UINT_ZERO
    assert (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance == pre_deposit_bal


@pytest.mark.asyncio
# TODO: enter values
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_deposit_withdraw(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, _, starknet_state = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e27)))
    decimals = (await zk_pad_staking.decimals().call()).result.decimals
    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *amount])
    pre_deposit_bal = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*amount, owner_account.contract_address])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    assert (await zk_pad_staking.totalFloat().call()).result.float == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    user_token_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_token_balance) == from_uint(
        pre_deposit_bal) - from_uint(amount)

    set_block_timestamp(
        starknet_state, get_block_timestamp(starknet_state) + days_to_seconds(365) + 1)
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdraw",
                                 [*amount, owner_account.contract_address, owner_account.contract_address])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == UINT_ZERO
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == 0
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == UINT_ZERO
    assert (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance == pre_deposit_bal


@pytest.mark.asyncio
async def test_atomic_deposit_redeem(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, _, _, starknet_state = contracts_factory
    decimals = (await zk_pad_staking.decimals().call()).result.decimals
    # max approve
    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *INIT_SUPPLY],
    )
    pre_deposit_bal = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*INIT_SUPPLY, owner_account.contract_address])
    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == INIT_SUPPLY
    assert (await zk_pad_staking.totalFloat().call()).result.float == INIT_SUPPLY
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(INIT_SUPPLY))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == INIT_SUPPLY
    user_token_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_token_balance) == from_uint(
        pre_deposit_bal) - from_uint(INIT_SUPPLY)

    set_block_timestamp(
        starknet_state, get_block_timestamp(starknet_state) + days_to_seconds(365) + 1)
    amount_to_redeem = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "redeem",
                                 [*amount_to_redeem,
                                  owner_account.contract_address, owner_account.contract_address])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == UINT_ZERO
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == 0
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == UINT_ZERO
    assert (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance == pre_deposit_bal


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_deposit_with_not_enough_approval(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, _, _ = contracts_factory
    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *to_uint(int(amount / 2))])
    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *to_uint(int(amount / 2))],
    )
    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                               [*to_uint(int(amount)), owner_account.contract_address]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_deposit_with_no_approval(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, _, _ = contracts_factory
    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                               [*to_uint(amount), owner_account.contract_address]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_atomic_enter_exit_single_pool(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e27)))
    decimals = (await zk_pad_staking.decimals().call()).result.decimals
    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*amount, owner_account.contract_address])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy1.contract_address, *amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == amount
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                 [strategy1.contract_address, *to_uint(int(from_uint(amount) / 2))])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    assert (await zk_pad_staking.totalFloat().call()).result.float == to_uint(int(from_uint(amount) / 2))
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount

    holdings = (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings
    assert_approx_eq(from_uint(holdings), from_uint(amount) / 2, 2)

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                 [strategy1.contract_address, *to_uint(int(from_uint(amount) / 2))])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount

    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert_approx_eq(from_uint(total_float), from_uint(amount), 2)

    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_atomic_enter_exit_multi_pool(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))
    decimals = (await zk_pad_staking.decimals().call()).result.decimals
    half_amount = to_uint(int(from_uint(amount) / 2))

    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*amount, owner_account.contract_address])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy1.contract_address, *half_amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == half_amount
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert_approx_eq(from_uint(total_float), int(from_uint(amount) / 2), 2)

    strategy2 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy2.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy2.contract_address, *half_amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    assert_approx_eq(from_uint((await zk_pad_staking.totalStrategyHoldings().call()).result.holdings),
                     from_uint(amount), 2)
    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert 2 >= from_uint(total_float)

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                 [strategy1.contract_address, *half_amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == half_amount
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert_approx_eq(from_uint(total_float), from_uint(half_amount), 2)
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                 [strategy2.contract_address, *half_amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(
        remove_lock_time_bonus(int(1e18)))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert_approx_eq(from_uint(total_float), from_uint(amount), 2)
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == calculate_lock_time_bonus(
        from_uint(amount))
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_deposit_into_strategy_with_not_enough_balance(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))

    half_amount = to_uint(int(from_uint(amount) / 2))
    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *half_amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *half_amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*half_amount, owner_account.contract_address])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])
    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                               [strategy1.contract_address, *amount]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_withdraw_from_strategy_with_not_enough_balance(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))

    half_amount = to_uint(int(from_uint(amount) / 2))
    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *half_amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *half_amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*half_amount, owner_account.contract_address])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy1.contract_address, *half_amount])
    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                               [strategy1.contract_address, *amount]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_withdraw_from_strategy_without_trust(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))

    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*amount, owner_account.contract_address])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy1.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "distrustStrategy",
                                 [strategy1.contract_address])
    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                               [strategy1.contract_address, *amount]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_deposit_into_strategy_with_no_balance(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))

    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])

    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                               [strategy1.contract_address, *amount]))


@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e10, 1e12])))
async def test_fail_withdraw_from_strategy_with_no_balance(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, _ = contracts_factory
    amount = to_uint(bound(amount, int(1e5), int(1e36)))

    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])

    await assert_revert(owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdrawFromStrategy",
                                               [strategy1.contract_address, *amount]))


###########################################################
#                      HARVEST TESTS
###########################################################

@pytest.mark.asyncio
@pytest.mark.parametrize("amount", list(map(int, [1e8])))
async def test_profitable_harvest(contracts_factory, amount):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, starknet_state = contracts_factory
    total = to_uint(int(1.5e18 * amount / 1e18))
    amount = to_uint(bound(amount, int(1e5), int(1e36)))
    harvest_delay = (await zk_pad_staking.harvestDelay().call()).result.delay
    decimals = (await zk_pad_staking.decimals().call()).result.decimals

    # reset the supply of the token and the owner balance
    owner_balance = (await zk_pad_token.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "burn",
                                 [owner_account.contract_address, *owner_balance])

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [owner_account.contract_address, *total])
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *amount])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositForTime",
                                 [*amount, owner_account.contract_address, 365 * 2])

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositIntoStrategy",
                                 [strategy1.contract_address, *amount])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == amount
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert from_uint(user_vault_balance) == from_uint(amount)
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    assert (await zk_pad_staking.totalSupply().call()).result.totalSupply == amount
    vault_token_balance = (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert vault_token_balance == UINT_ZERO
    assert (await zk_pad_staking.convertToAssets(vault_token_balance).call()).result.assets == UINT_ZERO

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "transfer",
                                 [strategy1.contract_address, *to_uint(int(from_uint(amount) / 2))])

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == amount
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == amount
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert user_vault_balance == amount
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    assert (await zk_pad_staking.totalSupply().call()).result.totalSupply == amount
    vault_token_balance = (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert vault_token_balance == UINT_ZERO
    assert (await zk_pad_staking.convertToAssets(vault_token_balance).call()).result.assets == UINT_ZERO
    assert (await zk_pad_staking.lastHarvest().call()).result.time == 0
    assert (await zk_pad_staking.lastHarvestWindowStart().call()).result.res == 0

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "harvest",
                                 [1, strategy1.contract_address])
    starting_timestamp = get_block_timestamp(starknet_state)

    assert (await zk_pad_staking.lastHarvest().call()).result.time == starting_timestamp
    assert (await zk_pad_staking.lastHarvestWindowStart().call()).result.res == starting_timestamp

    assert (await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets == to_uint(int(1e18))
    total_strategy_holding = from_uint((await zk_pad_staking.totalStrategyHoldings().call()).result.holdings)
    assert_approx_eq(total_strategy_holding, from_uint(total), 1)
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    total_assets = to_uint(int(1.05e18 * from_uint(amount) / 1e18))
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == total_assets
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert user_vault_balance == amount
    assert (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets == amount
    assert (await zk_pad_staking.totalSupply().call()).result.totalSupply == total_assets
    vault_token_balance = (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert vault_token_balance == to_uint(
        int(0.05e18 * from_uint(amount) / 1e18))
    assert (await zk_pad_staking.convertToAssets(vault_token_balance).call()).result.assets == to_uint(
        int(0.05e18 * from_uint(amount) / 1e18))

    advance_clock(starknet_state, int(harvest_delay / 2))

    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == total
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    assert from_uint((await zk_pad_staking.totalAssets().call()).result.totalManagedAssets) >= from_uint(amount)
    assert from_uint((await zk_pad_staking.totalAssets().call()).result.totalManagedAssets) <= from_uint(total)
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert user_vault_balance == amount
    assert (await zk_pad_staking.totalSupply().call()).result.totalSupply == to_uint(
        int(1.05e18 * from_uint(amount) / 1e18))
    vault_token_balance = (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert vault_token_balance == to_uint(
        int(0.05e18 * from_uint(amount) / 1e18))

    assets = (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets
    assert from_uint(assets) >= from_uint(amount)
    assert from_uint(assets) <= int(1.25e18 * from_uint(amount) / 1e18)
    assert from_uint((await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets) >= int(1e18)
    assert from_uint((await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets) <= int(
        1.25e18)

    advance_clock(starknet_state, harvest_delay)

    assert (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings == total
    assert (await zk_pad_staking.totalFloat().call()).result.float == UINT_ZERO
    assert (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets == total
    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    assert user_vault_balance == amount
    assert (await zk_pad_staking.totalSupply().call()).result.totalSupply == to_uint(
        int(1.05e18 * from_uint(amount) / 1e18))
    vault_token_balance = (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance
    assert vault_token_balance == to_uint(
        int(0.05e18 * from_uint(amount) / 1e18))

    assets = (await zk_pad_staking.convertToAssets(user_vault_balance).call()).result.assets
    assert from_uint(assets) >= int(1.4e18 * from_uint(amount) / 1e18)
    assert from_uint(assets) <= int(1.5e18 * from_uint(amount) / 1e18)
    assert from_uint((await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets) >= int(
        1.4e18)
    assert from_uint((await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets) <= int(
        1.5e18)

    advance_clock(starknet_state, days_to_seconds(365 * 2))

    user_deposit_amount = (await zk_pad_staking.getUserDeposit(owner_account.contract_address,
                                                               zk_pad_token.contract_address).call()).result.amount
    assert user_deposit_amount == amount

    user_vault_balance = (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "withdraw",
                                 [*user_vault_balance, owner_account.contract_address, owner_account.contract_address])

    assert from_uint((await zk_pad_staking.convertToAssets(to_uint(10 ** decimals)).call()).result.assets) >= (
        int(1.4e18))
    total_strategy_holding = (await zk_pad_staking.totalStrategyHoldings().call()).result.holdings
    total_assets = (await zk_pad_staking.totalAssets().call()).result.totalManagedAssets
    total_float = (await zk_pad_staking.totalFloat().call()).result.float
    assert from_uint(total_strategy_holding) == from_uint(
        total_assets) - from_uint(total_float)
    assert from_uint(total_float) >= 0
    assert from_uint(total_assets) >= 0


@pytest.mark.asyncio
async def test_updating_harvest_delay(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, starknet_state = contracts_factory

    assert (await zk_pad_staking.harvestDelay().call()).result.delay == 6 * 60 * 60
    assert (await zk_pad_staking.nextHarvestDelay().call()).result.delay == 0

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "setHarvestDelay", [12 * 60 * 60])

    assert (await zk_pad_staking.harvestDelay().call()).result.delay == 6 * 60 * 60
    assert (await zk_pad_staking.nextHarvestDelay().call()).result.delay == 12 * 60 * 60

    strategy1 = await deploy_contract_func("tests/mocks/test_mock_ERC20_strategy.cairo",
                                           [zk_pad_token.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "trustStrategy",
                                 [strategy1.contract_address])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "harvest",
                                 [1, strategy1.contract_address])

    assert (await zk_pad_staking.harvestDelay().call()).result.delay == 12 * 60 * 60
    assert (await zk_pad_staking.nextHarvestDelay().call()).result.delay == 0


@pytest.mark.asyncio
async def test_claim_fees(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, _, deploy_contract_func, starknet_state = contracts_factory
    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "approve",
                                 [zk_pad_staking.contract_address, *INIT_SUPPLY])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "depositForTime",
                                 [*INIT_SUPPLY, owner_account.contract_address, 365 * 2])

    advance_clock(starknet_state, days_to_seconds(365 * 2))
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "transfer",
                                 [zk_pad_staking.contract_address, *INIT_SUPPLY])

    assert (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance == INIT_SUPPLY
    assert (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance == UINT_ZERO

    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "claimFees", [*INIT_SUPPLY])

    assert (await zk_pad_staking.balanceOf(zk_pad_staking.contract_address).call()).result.balance == UINT_ZERO
    assert (await zk_pad_staking.balanceOf(owner_account.contract_address).call()).result.balance == INIT_SUPPLY


@pytest.mark.asyncio
async def test_reward_system(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, starknet_state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    stake_amount = INIT_SUPPLY

    await owner.send_transaction(owner_account, zk_pad_token.contract_address, "mint",
                                 [user1_account.contract_address, *stake_amount])

    # max approve
    await user1.send_transaction(
        user1_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *stake_amount],
    )
    user_balance_before_initial_deposit = (
        await zk_pad_token.balanceOf(user1_account.contract_address).call()).result.balance
    await user1.send_transaction(user1_account, zk_pad_staking.contract_address, "deposit",
                                 [*stake_amount, user1_account.contract_address])

    user_balance_after_initial_deposit = (
        await zk_pad_token.balanceOf(user1_account.contract_address).call()).result.balance

    END_BLOCK = (await zk_pad_staking.endBlock().call()).result.block

    set_block_number(starknet_state, END_BLOCK - 2)

    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *INIT_SUPPLY],
    )
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "deposit",
                                 [*INIT_SUPPLY, owner_account.contract_address])

    set_block_number(starknet_state, END_BLOCK - 1)
    pending_rewards = (
        await zk_pad_staking.calculatePendingRewards(user1_account.contract_address).call()).result.rewards

    assert pending_rewards != UINT_ZERO
    tx = await user1.send_transaction(user1_account, zk_pad_staking.contract_address, "harvestRewards", [])
    user_balance = (await zk_pad_token.balanceOf(user1_account.contract_address).call()).result.balance
    event_signature = get_selector_from_name("HarvestRewards")
    assert next(
        (x for x in tx.raw_events if event_signature in x.keys), None) is not None

    assert from_uint(user_balance) > from_uint(
        user_balance_after_initial_deposit)


# Bound a value between a min and max.
# https://github.com/Rari-Capital/vaults/blob/c8fdddc2a699f8c577e70878998a3eaa7d519f3f/src/test/Vault.t.sol#L971
def bound(x: int, min: int, max: int):
    assert min <= max
    size = max - min
    uint256_max = (2 ** 256) - 1
    if max != uint256_max:
        size += 1  # Make the max inclusive.
    if size == 0:
        return min  # Using max would be equivalent as well.
    # Ensure max is inclusive in cases where x != 0 and max is at uint max.
    if max == uint256_max and x != 0:
        x -= 1  # Accounted for later.

    if x < min:
        x += size * (((min - x) / size) + 1)
    result = min + ((x - min) % size)

    # Account for decrementing x to make max inclusive.
    if max == uint256_max and x != 0:
        result += 1
    return result
