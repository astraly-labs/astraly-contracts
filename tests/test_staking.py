import pytest
from utils import (
    Signer, to_uint, str_to_felt, MAX_UINT256, get_contract_def, cached_contract, assert_revert, assert_event_emitted, get_block_timestamp
)
from starkware.starknet.definitions.error_codes import StarknetErrorCode
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


@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def('openzeppelin/account/Account.cairo')
    zk_pad_token_def = get_contract_def('ZkPadToken.cairo')
    zk_pad_stake_def = get_contract_def('ZkPadStaking.cairo')
    return account_def, zk_pad_token_def, zk_pad_stake_def


@pytest.fixture(scope='module')
async def contacts_init(contract_defs, get_starknet):
    starknet = get_starknet
    account_def, zk_pad_token_def, zk_pad_stake_def = contract_defs

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

    zk_pad_stake = await starknet.deploy(
        contract_def=zk_pad_stake_def,
        constructor_calldata=[
            NAME,
            SYMBOL,
            zk_pad_token.contract_address,
            owner_account.contract_address
        ],
    )

    return (
        owner_account,
        zk_pad_token,
        zk_pad_stake
    )


@pytest.fixture
async def contracts_factory(contract_defs, contacts_init, get_starknet):
    account_def, zk_pad_token_def, zk_pad_stake_def = contract_defs
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
        account_def, _, _ = contract_defs
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
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, _ = contracts_factory

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
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, _ = contracts_factory

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
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, _, _ = contracts_factory

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
    await assert_revert(user3.send_transaction(
        user3_account,
        zk_pad_staking.contract_address,
        "withdraw",
        [*to_uint(1), user3_account.contract_address,
         user1_account.contract_address],
    ), error_code=StarknetErrorCode.TRANSACTION_FAILED)


@pytest.mark.asyncio
async def test_deposit_lp(contracts_factory):
    zk_pad_token, zk_pad_staking, owner_account, deploy_account_func, deploy_contract_func, state = contracts_factory

    user1 = Signer(2345)
    user1_account = await deploy_account_func(user1.public_key)

    deposit_amount = 10_000
    boost_value = int(2.5 * 10)

    mint_calculator = await deploy_contract_func("tests/mocks/test_mint_calculator.cairo")
    mock_lp_token = await deploy_contract_func("tests/mocks/test_erc20.cairo", [
        str_to_felt("ZKP ETH LP"),
        str_to_felt("ZKP/ETH"),
        DECIMALS,
        *to_uint(deposit_amount),
        owner_account.contract_address
    ])
    await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "set_stake_boost", [boost_value])

    add_whitelisted_token_tx = await owner.send_transaction(owner_account, zk_pad_staking.contract_address, "add_whitelisted_token", [
        mock_lp_token.contract_address,
        mint_calculator.contract_address
    ])

    assert (
        await zk_pad_staking.is_token_whitelisted(mock_lp_token.contract_address).invoke()
    ).result.res == 1

    await owner.send_transaction(
        owner_account,
        mock_lp_token.contract_address,
        "transfer",
        [user1_account.contract_address, *to_uint(deposit_amount)],
    )

    assert (
        await mock_lp_token.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(deposit_amount)

    assert (
        await mint_calculator.get_amount_to_mint(to_uint(deposit_amount)).invoke()
    ).result.amount == to_uint(deposit_amount)

    current_boost_value = (await zk_pad_staking.get_current_boost_value().invoke()).result.res
    assert boost_value == current_boost_value
    expect_to_mint = int((deposit_amount * current_boost_value) / 10)
    assert (
        await zk_pad_staking.get_xzkp_out(mock_lp_token.contract_address, to_uint(deposit_amount)).invoke()
    ).result.res == to_uint(expect_to_mint)

    await user1.send_transaction(
        user1_account,
        mock_lp_token.contract_address,
        "approve",
        [zk_pad_staking.contract_address, *to_uint(deposit_amount)]
    )

    timestamp = get_block_timestamp(state)
    one_year = 60 * 60 * 24 * 365
    mint_transaction = await user1.send_transaction(
        user1_account,
        zk_pad_staking.contract_address,
        "lp_mint",
        [mock_lp_token.contract_address, *
            to_uint(deposit_amount), user1_account.contract_address, timestamp + one_year]
    )

    assert (
        await zk_pad_staking.balanceOf(user1_account.contract_address).invoke()
    ).result.balance == to_uint(expect_to_mint)

    assert (
        await zk_pad_staking.get_user_unlock_time(user1_account.contract_address).invoke()
    ).result.unlock_time == timestamp + one_year

    assert (
        await zk_pad_staking.get_user_tokens_mask(user1_account.contract_address).invoke()
    ).result.tokens_mask in add_whitelisted_token_tx.result.response

    user_staked_tokens = (await zk_pad_staking.get_user_staked_tokens(user1_account.contract_address).invoke()).result.tokens
    assert mock_lp_token.contract_address in user_staked_tokens
