import pytest
from utils import (
    Signer, to_uint, str_to_felt, MAX_UINT256, get_contract_def, cached_contract, assert_event_emitted
)
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import Starknet

INIT_SUPPLY = to_uint(1_000_000)
CAP = to_uint(1_000_000_000_000)
UINT_ONE = to_uint(1)
UINT_ZERO = to_uint(0)
NAME = str_to_felt("xZkPad")
SYMBOL = str_to_felt("xZKP")
DECIMALS = 18

owner = Signer(1234)
user1 = Signer(2345)
user2 = Signer(3456)
user3 = Signer(4567)


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def('openzeppelin/account/Account.cairo')
    zk_pad_token_def = get_contract_def('ZkPadToken.cairo')
    zk_pad_stake_def = get_contract_def('ZkPadStaking.cairo')
    return account_def, zk_pad_token_def, zk_pad_stake_def


@pytest.fixture(scope='module')
async def contacts_init(contract_defs):
    starknet = await Starknet.empty()
    account_def, zk_pad_token_def, zk_pad_stake_def = contract_defs

    owner_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[owner.public_key]
    )
    user1_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[user1.public_key]
    )
    user2_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[user2.public_key]
    )
    user3_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[user3.public_key]
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

    zk_pad_stake = await starknet.deploy(
        contract_def=zk_pad_stake_def,
        constructor_calldata=[
            NAME,
            SYMBOL,
            zk_pad_token.contract_address,
        ],
    )

    return (
        starknet.state,
        owner_account,
        user1_account,
        user2_account,
        user3_account,
        zk_pad_token,
        zk_pad_stake
    )


@pytest.fixture
def contracts_factory(contract_defs, contacts_init):
    account_def, zk_pad_token_def, zk_pad_stake_def = contract_defs
    state, owner_account, user1_account, user2_account, user3_account, zk_pad_token, zk_pad_stake = contacts_init
    _state = state.copy()
    token = cached_contract(_state, zk_pad_token_def, zk_pad_token)
    stake = cached_contract(_state, zk_pad_stake_def, zk_pad_stake)
    owner_cached = cached_contract(_state, account_def, owner_account)
    user1_cached = cached_contract(_state, account_def, user1_account)
    user2_cached = cached_contract(_state, account_def, user2_account)
    user3_cached = cached_contract(_state, account_def, user3_account)
    return token, stake, owner_cached, user1_cached, user2_cached, user3_cached


@pytest.mark.asyncio
@pytest.mark.order(1)
async def test_init(contracts_factory):
    zk_pad_token, zk_pad_staking, _, _, _, _ = contracts_factory
    assert (await zk_pad_staking.name().invoke()).result.name == NAME
    assert (await zk_pad_staking.symbol().invoke()).result.symbol == SYMBOL
    assert (await zk_pad_staking.decimals().invoke()).result.decimals == 18
    assert (await zk_pad_staking.asset().invoke()).result.assetTokenAddress == zk_pad_token.contract_address
    assert (await zk_pad_staking.totalAssets().invoke()).result.totalManagedAssets == to_uint(0)


@pytest.mark.asyncio
async def test_conversions(contracts_factory):
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
    zk_pad_token, zk_pad_staking, owner_account, user1_account, _, _ = contracts_factory

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

    # deposit asset tokens to the vault, get shares
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "deposit",
        [*amount, user1_account.contract_address],
    )
    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == amount
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Deposit", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        *amount,
        *tx.result.response
    ])
    assert (
               await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(90_000)

    # redeem vault shares, get back assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "redeem",
        [*amount, user1_account.contract_address,
         user1_account.contract_address],
    )

    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(0)
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
    zk_pad_token, zk_pad_staking, owner_account, user1_account, _, _ = contracts_factory

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
           ).result.balance == to_uint(0)

    # max approve
    await user1.send_transaction(
        user1_account, zk_pad_token.contract_address, "approve", [
            zk_pad_staking.contract_address, *MAX_UINT256]
    )

    amount = to_uint(10_000)

    # mint shares for assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "mint",
        [*amount, user1_account.contract_address],
    )

    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == amount
    assert_event_emitted(tx, zk_pad_staking.contract_address, "Deposit", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        *amount,
        *tx.result.response
    ])

    assert (
               await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(90_000)

    # withdraw shares, get back assets
    tx = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*amount, user1_account.contract_address,
         user1_account.contract_address],
    )

    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(0)

    assert_event_emitted(tx, zk_pad_staking.contract_address, "Withdraw", data=[
        user1_account.contract_address,
        user1_account.contract_address,
        user1_account.contract_address,
        *amount,
        *tx.result.response,
    ])
    assert (
               await zk_pad_token.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(100_000)


@pytest.mark.asyncio
async def test_allowances(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, user1_account, user2_account, user3_account = contracts_factory
    amount = to_uint(100_000)

    # mint assets to user1
    await owner.send_transaction(
        owner_account,
        zk_pad_token.contract_address,
        "mint",
        [user1_account.contract_address, *amount],
    )
    assert (await zk_pad_token.balanceOf(user1_account.contract_address).invoke()).result.balance == amount

    # have user1 get shares in vault
    await user1.send_transaction(
        user1_account, zk_pad_token.contract_address, "approve", [
            zk_pad_staking.contract_address, *MAX_UINT256]
    )
    await user1.send_transaction(
        user1_account, zk_pad_staking.contract_address, "mint", [
            *amount, user1_account.contract_address]
    )

    # max approve user2
    await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "approve",
        [user2_account.contract_address, *MAX_UINT256],
    )

    # approve user3 for 10K
    await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "approve",
        [user3_account.contract_address, *to_uint(10_000)],
    )

    #
    # have user2 withdraw 50K assets from user1 vault position
    #
    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(100_000)
    assert (
               await zk_pad_staking.balanceOf(user2_account.contract_address).invoke()
           ).result.balance == to_uint(0)
    assert (
               await zk_pad_token.balanceOf(user2_account.contract_address).invoke()
           ).result.balance == to_uint(0)

    await user2.send_transaction(
        user2_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(50_000), user2_account.contract_address,
         user1_account.contract_address],
    )

    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(50_000)
    assert (
               await zk_pad_staking.balanceOf(user2_account.contract_address).invoke()
           ).result.balance == to_uint(0)
    assert (
               await zk_pad_token.balanceOf(user2_account.contract_address).invoke()
           ).result.balance == to_uint(50_000)
    assert (
               await zk_pad_staking.allowance(
                   user1_account.contract_address, user2_account.contract_address
               ).invoke()
           ).result.remaining == MAX_UINT256

    #
    # have user3 withdraw 10K assets from user1 vault position
    #
    assert (
               await zk_pad_staking.balanceOf(user3_account.contract_address).invoke()
           ).result.balance == to_uint(0)
    assert (
               await zk_pad_token.balanceOf(user3_account.contract_address).invoke()
           ).result.balance == to_uint(0)

    await user3.send_transaction(
        user3_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(10_000), user3_account.contract_address,
         user1_account.contract_address],
    )

    assert (
               await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
           ).result.balance == to_uint(40_000)
    assert (
               await zk_pad_staking.balanceOf(user3_account.contract_address).invoke()
           ).result.balance == to_uint(0)
    assert (
               await zk_pad_token.balanceOf(user3_account.contract_address).invoke()
           ).result.balance == to_uint(10_000)
    assert (
               await zk_pad_staking.allowance(
                   user1_account.contract_address, user3_account.contract_address
               ).invoke()
           ).result.remaining == to_uint(0)

    # user3 tries withdrawing again, has insufficient allowance, :burn:
    with pytest.raises(StarkException):
        await user3.send_transaction(
            user3_account,
            zk_pad_staking.contract_address,
            "withdraw",
            [*to_uint(1), user3_account.contract_address,
             user1_account.contract_address],
        )
