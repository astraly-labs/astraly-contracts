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
referral_path = "Referral/AstralyReferral.cairo"

deployer = MockSigner(1234321)
admin1 = MockSigner(2345432)

REFERRAL_CUT = to_uint(4)  # 25%


@pytest.fixture(scope="module")
def contract_defs():
    account_def = get_contract_def(account_path)
    referral_def = get_contract_def(referral_path)

    return (
        account_def,
        referral_def,
    )


@pytest_asyncio.fixture(scope="module")
async def contracts_init(contract_defs, get_starknet):
    starknet = get_starknet
    (
        account_def,
        referral_def
    ) = contract_defs
    await starknet.declare(contract_class=account_def)
    deployer_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[deployer.public_key]
    )
    admin1_account = await starknet.deploy(
        contract_class=account_def, constructor_calldata=[admin1.public_key]
    )

    await starknet.declare(contract_class=referral_def)
    referral = await starknet.deploy(
        contract_class=referral_def,
        constructor_calldata=[admin1_account.contract_address, *REFERRAL_CUT],
    )

    return (
        deployer_account,
        admin1_account,
        referral
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init, get_starknet):
    (
        account_def,
        referral_def
    ) = contract_defs
    (
        deployer_account,
        admin1_account,
        referral
    ) = contracts_init
    _state = get_starknet.state.copy()
    deployer_cached = cached_contract(_state, account_def, deployer_account)
    admin1_cached = cached_contract(_state, account_def, admin1_account)
    referral_cached = cached_contract(_state, referral_def, referral)

    return (
        deployer_cached,
        admin1_cached,
        referral_cached,
        _state,
    )


@pytest.mark.asyncio
async def test_set_referral_cut(contracts_factory):
    (deployer_account, admin_account, referral, state) = contracts_factory
    # Check cut is as defined in constructor
    cut = (await referral.get_referral_cut().call()).result.res
    assert cut == REFERRAL_CUT
    # Reverts if caller is not owner
    await assert_revert(
        deployer.send_transaction(
            deployer_account,
            referral.contract_address,
            "set_referral_cut",
            [*to_uint(5)],  # 20%
        ),
        reverted_with=f"AccessControl: caller is missing role {str_to_felt('OWNER')}",
    )
    # Update referral cut
    tx = await admin1.send_transaction(admin_account, referral.contract_address, 'set_referral_cut', [*to_uint(5)])
    # Check cut has been successfuly updated
    cut = (await referral.get_referral_cut().call()).result.res
    assert cut == to_uint(5)


@pytest.mark.asyncio
async def test_record_referral(contracts_factory):
    (deployer_account, admin_account, referral, state) = contracts_factory

    # Reverts if caller is not owner
    await assert_revert(
        deployer.send_transaction(
            deployer_account,
            referral.contract_address,
            "record_referral",
            [deployer_account.contract_address, admin_account.contract_address],
        ),
        reverted_with=f"AccessControl: caller is missing role {str_to_felt('OWNER')}",
    )

    # Can not refer itself
    await assert_revert(
        admin1.send_transaction(
            admin_account,
            referral.contract_address,
            "record_referral",
            [deployer_account.contract_address, deployer_account.contract_address],
        ),
        reverted_with="record_referral::self referral is not allowed",
    )

    # Check deployer has no referrer
    referrer = (await referral.get_referrer(deployer_account.contract_address).call()).result.res
    assert referrer == 0
    # Check admin has no referrals
    referrals_count = (await referral.get_referral_count(admin_account.contract_address).call()).result.res
    assert referrals_count == 0
    # Deployer is referred by admin
    tx = await admin1.send_transaction(admin_account, referral.contract_address, 'record_referral', [deployer_account.contract_address, admin_account.contract_address])
    # Check deployer is referred by admin
    referrer = (await referral.get_referrer(deployer_account.contract_address).call()).result.res
    assert referrer == admin_account.contract_address
    # Check admin has 1 referral
    referrals_count = (await referral.get_referral_count(admin_account.contract_address).call()).result.res
    assert referrals_count == 1

    # Can only be referred once
    await assert_revert(
        admin1.send_transaction(
            admin_account,
            referral.contract_address,
            "record_referral",
            [deployer_account.contract_address, admin_account.contract_address],
        ),
        reverted_with="is already referred",
    )
