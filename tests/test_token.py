import pytest
import asyncio

from starkware.starknet.testing.starknet import Starknet
from utils import (
    Signer, to_uint, add_uint, sub_uint, str_to_felt, MAX_UINT256, ZERO_ADDRESS, INVALID_UINT256,
    TRUE, get_contract_def, cached_contract, assert_revert, assert_event_emitted, contract_path
)

recipient = Signer(123456789987654321)
owner = Signer(123456789876543210)

# testing vars
INIT_SUPPLY = to_uint(1000)
CAP = to_uint(1000)
AMOUNT = to_uint(200)
UINT_ONE = to_uint(1)
UINT_ZERO = to_uint(0)
NAME = str_to_felt("Astraly")
SYMBOL = str_to_felt("ZKP")
DECIMALS = 18


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
def contract_defs():
    account_def = get_contract_def(
        'openzeppelin/account/presets/Account.cairo')
    zk_pad_token_def = get_contract_def('AstralyToken.cairo')
    return account_def, zk_pad_token_def


@pytest.fixture(scope='module')
async def contracts_init(contract_defs):
    account_def, zk_pad_token_def = contract_defs
    starknet = await Starknet.empty()
    await starknet.declare(contract_class=account_def)
    recipient_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[recipient.public_key]
    )
    owner_account = await starknet.deploy(
        contract_class=account_def,
        constructor_calldata=[owner.public_key]
    )
    await starknet.declare(contract_class=zk_pad_token_def)
    erc20 = await starknet.deploy(
        contract_class=zk_pad_token_def,
        constructor_calldata=[
            NAME,
            SYMBOL,
            DECIMALS,
            *INIT_SUPPLY,
            recipient_account.contract_address,        # recipient
            owner_account.contract_address,
            *CAP,
        ]
    )
    return (
        starknet.state,
        recipient_account,
        owner_account,
        erc20
    )


@pytest.fixture
def contracts_factory(contract_defs, contracts_init):
    account_def, zk_pad_token_def = contract_defs
    state, account1, account2, erc20 = contracts_init
    _state = state.copy()
    account1 = cached_contract(_state, account_def, account1)
    account2 = cached_contract(_state, account_def, account2)
    erc20 = cached_contract(_state, zk_pad_token_def, erc20)
    return erc20, account1, account2


#
# Constructor
#


@pytest.mark.asyncio
async def test_constructor(contracts_factory):
    erc20, recipient_account, _ = contracts_factory

    # balanceOf recipient
    execution_info = await erc20.balanceOf(recipient_account.contract_address).invoke()
    assert execution_info.result.balance == INIT_SUPPLY

    # totalSupply
    execution_info = await erc20.totalSupply().invoke()
    assert execution_info.result.totalSupply == INIT_SUPPLY


@pytest.mark.asyncio
async def test_constructor_exceed_max_decimals(contracts_factory):
    _, recipient_account, owner_account = contracts_factory

    bad_decimals = 2**8 + 1

    starknet = await Starknet.empty()
    zk_pad_token_def = get_contract_def('AstralyToken.cairo')
    await assert_revert(
        starknet.deploy(
            contract_class=zk_pad_token_def,
            constructor_calldata=[
                NAME,
                SYMBOL,
                bad_decimals,
                *INIT_SUPPLY,
                recipient_account.contract_address,
                owner_account.contract_address,
                *CAP,
            ]),
        reverted_with="ERC20: decimals exceed 2^8"
    )


@pytest.mark.asyncio
async def test_name(contracts_factory):
    erc20, _, _ = contracts_factory
    execution_info = await erc20.name().invoke()
    assert execution_info.result.name == NAME


@pytest.mark.asyncio
async def test_symbol(contracts_factory):
    erc20, _, _ = contracts_factory
    execution_info = await erc20.symbol().invoke()
    assert execution_info.result.symbol == SYMBOL


@pytest.mark.asyncio
async def test_decimals(contracts_factory):
    erc20, _, _ = contracts_factory
    execution_info = await erc20.decimals().invoke()
    assert execution_info.result.decimals == DECIMALS


#
# approve
#


@pytest.mark.asyncio
async def test_approve(contracts_factory):
    erc20, account, spender = contracts_factory

    # check spender's allowance starts at zero
    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == UINT_ZERO

    # set approval
    return_bool = await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )
    assert return_bool.result.response == [TRUE]

    # check spender's allowance
    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == AMOUNT


@pytest.mark.asyncio
async def test_approve_emits_event(contracts_factory):
    erc20, account, spender = contracts_factory

    tx_exec_info = await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ])

    assert_event_emitted(
        tx_exec_info,
        from_address=erc20.contract_address,
        name='Approval',
        data=[
            account.contract_address,
            spender.contract_address,
            *AMOUNT
        ]
    )


@pytest.mark.asyncio
async def test_approve_from_zero_address(contracts_factory):
    erc20, _, spender = contracts_factory

    # Without using an account abstraction, the caller address
    # (get_caller_address) is zero
    await assert_revert(
        erc20.approve(spender.contract_address, AMOUNT).invoke(),
        reverted_with="ERC20: cannot approve from the zero address"
    )


@pytest.mark.asyncio
async def test_approve_to_zero_address(contracts_factory):
    erc20, account, _ = contracts_factory

    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            ZERO_ADDRESS,
            *UINT_ONE
        ]),
        reverted_with="ERC20: cannot approve to the zero address"
    )


@pytest.mark.asyncio
async def test_approve_invalid_uint256(contracts_factory):
    erc20, account, spender = contracts_factory

    await assert_revert(
        recipient.send_transaction(
            account, erc20.contract_address, 'approve', [
                spender.contract_address,
                *INVALID_UINT256
            ]),
        reverted_with="ERC20: amount is not a valid Uint256"
    )


#
# transfer
#


@pytest.mark.asyncio
async def test_transfer(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    # check original totalSupply
    execution_info = await erc20.balanceOf(recipient_account.contract_address).invoke()
    assert execution_info.result.balance == INIT_SUPPLY

    # check recipient original balance
    execution_info = await erc20.balanceOf(owner_account.contract_address).invoke()
    assert execution_info.result.balance == UINT_ZERO

    # transfer
    return_bool = await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'transfer', [
            owner_account.contract_address,
            *AMOUNT
        ]
    )
    assert return_bool.result.response == [TRUE]

    # check recipient_account balance
    execution_info = await erc20.balanceOf(recipient_account.contract_address).invoke()
    assert execution_info.result.balance == sub_uint(INIT_SUPPLY, AMOUNT)

    # check recipient balance
    execution_info = await erc20.balanceOf(owner_account.contract_address).invoke()
    assert execution_info.result.balance == AMOUNT

    # check totalSupply
    execution_info = await erc20.totalSupply().invoke()
    assert execution_info.result.totalSupply == INIT_SUPPLY


@pytest.mark.asyncio
async def test_transfer_emits_event(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    tx_exec_info = await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'transfer', [
            owner_account.contract_address,
            *AMOUNT
        ])

    assert_event_emitted(
        tx_exec_info,
        from_address=erc20.contract_address,
        name='Transfer',
        data=[
            recipient_account.contract_address,
            owner_account.contract_address,
            *AMOUNT
        ]
    )


@pytest.mark.asyncio
async def test_transfer_not_enough_balance(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    await assert_revert(recipient.send_transaction(
        recipient_account, erc20.contract_address, 'transfer', [
            owner_account.contract_address,
            *add_uint(INIT_SUPPLY, UINT_ONE)
        ]),
        reverted_with="ERC20: transfer amount exceeds balance"
    )


@pytest.mark.asyncio
async def test_transfer_to_zero_address(contracts_factory):
    erc20, account, _ = contracts_factory

    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'transfer', [
            ZERO_ADDRESS,
            *UINT_ONE
        ]),
        reverted_with="ERC20: cannot transfer to the zero address"
    )


@pytest.mark.asyncio
async def test_transfer_from_zero_address(contracts_factory):
    erc20, _, owner_account = contracts_factory

    # Without using an account abstraction, the caller address
    # (get_caller_address) is zero
    await assert_revert(
        erc20.transfer(owner_account.contract_address, UINT_ONE).invoke(),
        reverted_with="ERC20: cannot transfer from the zero address"
    )


@pytest.mark.asyncio
async def test_transfer_invalid_uint256(contracts_factory):
    erc20, account, owner_account = contracts_factory

    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'transfer', [
            owner_account.contract_address,
            *INVALID_UINT256
        ]),
        reverted_with="ERC20: amount is not a valid Uint256"
    )


#
# transferFrom
#


@pytest.mark.asyncio
async def test_transferFrom(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    # approve
    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *AMOUNT
        ]
    )
    # transferFrom
    return_bool = await owner.send_transaction(
        owner_account, erc20.contract_address, 'transferFrom', [
            recipient_account.contract_address,
            owner_account.contract_address,
            *AMOUNT
        ]
    )
    assert return_bool.result.response == [TRUE]

    # check recipient_account balance
    execution_info = await erc20.balanceOf(recipient_account.contract_address).invoke()
    assert execution_info.result.balance == sub_uint(INIT_SUPPLY, AMOUNT)

    # check recipient balance
    execution_info = await erc20.balanceOf(owner_account.contract_address).invoke()
    assert execution_info.result.balance == AMOUNT

    # check owner_account allowance after tx
    execution_info = await erc20.allowance(recipient_account.contract_address, owner_account.contract_address).invoke()
    assert execution_info.result.remaining == UINT_ZERO


@pytest.mark.asyncio
async def test_transferFrom_emits_event(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    # approve
    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *AMOUNT
        ])

    # transferFrom
    tx_exec_info = await owner.send_transaction(
        owner_account, erc20.contract_address, 'transferFrom', [
            recipient_account.contract_address,
            owner_account.contract_address,
            *AMOUNT
        ])

    assert_event_emitted(
        tx_exec_info,
        from_address=erc20.contract_address,
        name='Transfer',
        data=[
            recipient_account.contract_address,
            owner_account.contract_address,
            *AMOUNT
        ]
    )


@pytest.mark.asyncio
async def test_transferFrom_greater_than_allowance(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory
    # we use the same signer to control the main and the owner_account accounts
    # this is ok since they're still two different accounts

    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *AMOUNT
        ]
    )

    fail_amount = add_uint(AMOUNT, UINT_ONE)

    # increasing the transfer amount above allowance
    await assert_revert(recipient.send_transaction(
        recipient_account, erc20.contract_address, 'transferFrom', [
            recipient_account.contract_address,
            owner_account.contract_address,
            *fail_amount
        ]),
        reverted_with="ERC20: insufficient allowance"
    )


@pytest.mark.asyncio
async def test_transferFrom_from_zero_address(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    await assert_revert(recipient.send_transaction(
        recipient_account, erc20.contract_address, 'transferFrom', [
            ZERO_ADDRESS,
            owner_account.contract_address,
            *AMOUNT
        ]),
        reverted_with="ERC20: insufficient allowance"
    )


@pytest.mark.asyncio
async def test_transferFrom_to_zero_address(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *UINT_ONE
        ]
    )

    await assert_revert(owner.send_transaction(
        owner_account, erc20.contract_address, 'transferFrom', [
            recipient_account.contract_address,
            ZERO_ADDRESS,
            *UINT_ONE
        ]),
        reverted_with="ERC20: cannot transfer to the zero address"
    )


#
# increaseAllowance
#


@pytest.mark.asyncio
async def test_increaseAllowance(contracts_factory):
    erc20, account, spender = contracts_factory

    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == UINT_ZERO

    # set approve
    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )

    # check allowance
    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == AMOUNT

    # increase allowance
    return_bool = await recipient.send_transaction(
        account, erc20.contract_address, 'increaseAllowance', [
            spender.contract_address,
            *AMOUNT
        ]
    )
    assert return_bool.result.response == [TRUE]

    # check spender's allowance increased
    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == add_uint(AMOUNT, AMOUNT)


@pytest.mark.asyncio
async def test_increaseAllowance_emits_event(contracts_factory):
    erc20, account, spender = contracts_factory

    # set approve
    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ])

    # increase allowance
    tx_exec_info = await recipient.send_transaction(
        account, erc20.contract_address, 'increaseAllowance', [
            spender.contract_address,
            *AMOUNT
        ])

    new_allowance = add_uint(AMOUNT, AMOUNT)

    assert_event_emitted(
        tx_exec_info,
        from_address=erc20.contract_address,
        name='Approval',
        data=[
            account.contract_address,
            spender.contract_address,
            *new_allowance
        ]
    )


@pytest.mark.asyncio
async def test_increaseAllowance_overflow(contracts_factory):
    erc20, account, spender = contracts_factory

    # approve max
    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *MAX_UINT256
        ]
    )

    # overflow_amount adds (1, 0) to (2**128 - 1, 2**128 - 1)
    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'increaseAllowance', [
            spender.contract_address,
            *UINT_ONE
        ]),
        reverted_with="ERC20: allowance overflow"
    )


@pytest.mark.asyncio
async def test_increaseAllowance_to_zero_address(contracts_factory):
    erc20, account, spender = contracts_factory

    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )

    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'increaseAllowance', [
            ZERO_ADDRESS,
            *AMOUNT
        ])
    )


@pytest.mark.asyncio
async def test_increaseAllowance_from_zero_address(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *AMOUNT
        ]
    )

    await assert_revert(
        erc20.increaseAllowance(
            owner_account.contract_address, AMOUNT).invoke()
    )


#
# decreaseAllowance
#


@pytest.mark.asyncio
async def test_decreaseAllowance(contracts_factory):
    erc20, account, spender = contracts_factory

    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == UINT_ZERO

    # set approve
    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )

    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == AMOUNT

    # decrease allowance
    return_bool = await recipient.send_transaction(
        account, erc20.contract_address, 'decreaseAllowance', [
            spender.contract_address,
            *UINT_ONE
        ]
    )
    assert return_bool.result.response == [TRUE]

    new_allowance = sub_uint(AMOUNT, UINT_ONE)

    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == new_allowance


@pytest.mark.asyncio
async def test_decreaseAllowance_emits_event(contracts_factory):
    erc20, account, spender = contracts_factory

    # set approve
    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *INIT_SUPPLY
        ])

    # decrease allowance
    tx_exec_info = await recipient.send_transaction(
        account, erc20.contract_address, 'decreaseAllowance', [
            spender.contract_address,
            *AMOUNT
        ])

    new_allowance = sub_uint(INIT_SUPPLY, AMOUNT)

    assert_event_emitted(
        tx_exec_info,
        from_address=erc20.contract_address,
        name='Approval',
        data=[
            account.contract_address,
            spender.contract_address,
            *new_allowance
        ]
    )


@pytest.mark.asyncio
async def test_decreaseAllowance_overflow(contracts_factory):
    erc20, account, spender = contracts_factory

    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )

    execution_info = await erc20.allowance(account.contract_address, spender.contract_address).invoke()
    assert execution_info.result.remaining == AMOUNT

    allowance_plus_one = add_uint(AMOUNT, UINT_ONE)

    # increasing the decreased allowance amount by more than the spender's allowance
    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'decreaseAllowance', [
            spender.contract_address,
            *allowance_plus_one
        ]),
        reverted_with="ERC20: allowance below zero"
    )


@pytest.mark.asyncio
async def test_decreaseAllowance_to_zero_address(contracts_factory):
    erc20, account, spender = contracts_factory

    await recipient.send_transaction(
        account, erc20.contract_address, 'approve', [
            spender.contract_address,
            *AMOUNT
        ]
    )

    await assert_revert(recipient.send_transaction(
        account, erc20.contract_address, 'decreaseAllowance', [
            ZERO_ADDRESS,
            *AMOUNT
        ])
    )


@pytest.mark.asyncio
async def test_decreaseAllowance_from_zero_address(contracts_factory):
    erc20, recipient_account, owner_account = contracts_factory

    await recipient.send_transaction(
        recipient_account, erc20.contract_address, 'approve', [
            owner_account.contract_address,
            *AMOUNT
        ]
    )

    await assert_revert(
        erc20.decreaseAllowance(
            owner_account.contract_address, AMOUNT).invoke()
    )


@pytest.mark.asyncio
async def test_decreaseAllowance_invalid_uint256(contracts_factory):
    erc20, account, spender = contracts_factory

    await assert_revert(
        recipient.send_transaction(
            account, erc20.contract_address, 'decreaseAllowance', [
                spender.contract_address,
                *INVALID_UINT256
            ]),
        reverted_with="ERC20: subtracted_value is not a valid Uint256"
    )
