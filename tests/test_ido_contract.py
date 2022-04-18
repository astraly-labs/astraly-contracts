import pytest
from utils import (
    Signer, to_uint, str_to_felt, MAX_UINT256, get_contract_def, cached_contract, assert_revert, assert_event_emitted
)
from starkware.starknet.definitions.error_codes import StarknetErrorCode
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import Starknet
from datetime import datetime, date, timedelta

TRUE = 1
FALSE = 0
NAME = str_to_felt("ZkPad")
SYMBOL = str_to_felt("ZKP")
DECIMALS = 18
INIT_SUPPLY = to_uint(1000)
CAP = to_uint(1000)

deployer = Signer(1234)
admin1   = Signer(2345)
staking  = Signer(3456)
sale_owner = Signer(4567)
zkp_recipient = Signer(123456789987654321)
zkp_owner = Signer(123456789876543210)

@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def('openzeppelin/account/Account.cairo')
    zk_pad_admin_def = get_contract_def('ZkPadAdmin.cairo')
    zk_pad_ido_def = get_contract_def('ZkPadIDOContract.cairo')
    zk_pad_token_def = get_contract_def('ZkPadToken.cairo')
    return account_def, zk_pad_admin_def, zk_pad_ido_def, zk_pad_token_def

@pytest.fixture(scope='module')
async def contacts_init(contract_defs):
    starknet = await Starknet.empty()
    account_def, zk_pad_admin_def, zk_pad_ido_def, zk_pad_token_def = contract_defs

    deployer_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[deployer.public_key]
    )
    admin1_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[admin1.public_key]
    )
    staking_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[staking.public_key]
    )
    sale_owner_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[sale_owner.public_key]
    )

    zkp_recipient_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[zkp_recipient.public_key]
    )
    
    zkp_owner_account = await starknet.deploy(
        contract_def=account_def,
        constructor_calldata=[zkp_owner.public_key]
    )

    zk_pad_admin = await starknet.deploy(
        contract_def=zk_pad_admin_def,
        constructor_calldata=[
            1,
            *[admin1_account.contract_address]
        ],
    )

    zk_pad_token = await starknet.deploy(
        contract_def=zk_pad_token_def,
        constructor_calldata=[
            NAME,
            SYMBOL,
            DECIMALS,
            *INIT_SUPPLY,
            zkp_recipient_account.contract_address,        # recipient
            zkp_owner_account.contract_address,
            *CAP,
            123124
        ]
    )

    zk_pad_ido = await starknet.deploy(
        contract_def=zk_pad_ido_def,
        constructor_calldata=[
            zk_pad_admin.contract_address,
            staking_account.contract_address
        ]
    )

    return (
        starknet.state,
        deployer_account,
        admin1_account,
        staking_account,
        sale_owner_account,
        zkp_recipient_account,
        zkp_owner_account,
        zk_pad_admin,
        zk_pad_token,
        zk_pad_ido
    )

@pytest.fixture
def contracts_factory(contract_defs, contacts_init):
    account_def, zk_pad_admin_def, zk_pad_ido_def, zk_pad_token_def = contract_defs
    state, deployer_account, admin1_account, staking_account, sale_owner_account, zkp_recipient_account, zkp_owner_account, zk_pad_admin, zk_pad_token, zk_pad_ido = contacts_init
    _state = state.copy()
    admin_cached = cached_contract(_state, zk_pad_admin_def, zk_pad_admin)
    deployer_cached = cached_contract(_state, account_def, deployer_account)
    admin1_cached = cached_contract(_state, account_def, admin1_account)
    staking_cached = cached_contract(_state, account_def, staking_account)
    owner_cached = cached_contract(_state, account_def, sale_owner_account)
    zkp_token_cached = cached_contract(_state, zk_pad_token_def, zk_pad_token)
    ido_cached = cached_contract(_state, zk_pad_ido_def, zk_pad_ido)
    return admin_cached, deployer_cached, admin1_cached, staking_cached, owner_cached, zkp_token_cached, ido_cached

@pytest.mark.asyncio
async def test_setup_sale_success_with_events(contracts_factory):
    admin_contract, _, admin_user, stakin_contract, owner_contract, zkp_token, ido = contracts_factory
    day = datetime.today()
    timeDelta30days = timedelta(days=30)
    sale_end = day + timeDelta30days
    token_unlock = sale_end + timeDelta30days
    
    tx = await admin1.send_transaction(
        admin_user,
        ido.contract_address,
        "set_sale_params",
        [
            zkp_token.contract_address,
            owner_contract.contract_address,
            100,
            100,
            int(sale_end.timestamp()),
            int(token_unlock.timestamp()),
            1000,
            10000
        ]
    )

    assert_event_emitted(tx, ido.contract_address, "sale_created", data=[
        owner_contract.contract_address,
        100,
        100,
        int(sale_end.timestamp()),
        int(token_unlock.timestamp())
    ])

    timeDeltaOneWeek = timedelta(weeks=1)
    reg_start = day + timeDeltaOneWeek
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

