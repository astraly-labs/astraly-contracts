%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_le, uint256_sub
from starkware.cairo.common.math import assert_not_equal, assert_not_zero, assert_nn_le, assert_lt
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address, get_block_timestamp

from openzeppelin.utils.constants import TRUE, FALSE
from openzeppelin.access.ownable import (Ownable_only_owner)
from openzeppelin.introspection.IERC165 import IERC165
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.security.safemath import uint256_checked_add, uint256_checked_mul, uint256_checked_div_rem

from contracts.openzeppelin.security.reentrancy_guard import ReentrancyGuard_start, ReentrancyGuard_end
from contracts.erc4626.ERC4626 import (
    name, symbol, totalSupply, decimals, balanceOf, allowance,
    transfer, transferFrom, approve,
    asset, totalAssets, convertToShares, convertToAssets, maxDeposit, previewDeposit,
    deposit, maxMint, previewMint, mint, maxWithdraw, previewWithdraw, withdraw,
    maxRedeem, previewRedeem, redeem)
from contracts.utils import uint256_is_zero

const IERC721_ID = 0x80ac58cd

@contract_interface
namespace IMintCalculator:
    func get_amount_to_mint(input : Uint256) -> (amount : Uint256):
    end
end

@event
func Deposit_lp(depositor : felt, receiver : felt, lp_address : felt, assets : Uint256, shares : Uint256):
end

@event
func Withdraw_lp(withdrawer : felt, receiver : felt, owner : felt, lp_token : felt, assets : Uint256, shares : Uint256):
end

@storage_var
func whitelisted_tokens(lp_token : felt) -> (mint_calculator_address : felt):
end

@storage_var
func deposits(user : felt, token_address : felt) -> (amount : Uint256):
end

@storage_var
func deposit_unlock_time(user : felt) -> (unlock_time : felt):
end

# value is multiplied by 10 to store floating points number in felt type
@storage_var
func stake_boost() -> (boost : felt):
end

#
# View
#

@view
func is_token_whitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt) -> (res : felt):
    let (is_whitelisted : felt) = whitelisted_tokens.read(lp_token)
    if is_whitelisted == FALSE:
        return (FALSE)
    end
    return (TRUE)
end

# Amount of xZKP a user will receive by providing LP token
@view
func get_xzkp_out{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt, input : Uint256) -> (res : Uint256):
    alloc_locals
    let (mint_calculator_address : felt) = whitelisted_tokens.read(lp_token)
    with_attr error_message("invalid mint calculator address"):
        assert_not_zero(mint_calculator_address)
    end
    with_attr error_message("invalid token amount or nft id"):
        let (is_zero) = uint256_is_zero(input)
        assert is_zero = FALSE
    end
    let (amount_to_mint : Uint256) = IMintCalculator.get_amount_to_mint(mint_calculator_address, input)

    let (current_boost : felt) = stake_boost.read()
    assert_not_zero(current_boost)
    let (value_multiplied : Uint256) = uint256_checked_mul(amount_to_mint, Uint256(0, current_boost))
    let (amount_after_boost : Uint256, _) = uint256_checked_div_rem(value_multiplied , Uint256(0, 10))

    return (amount_after_boost)
end

@view
func get_current_boost_value{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res: felt):
    let (res : felt) = stake_boost.read()
    return (res)
end

#
# Externals
#

@external
func add_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt, mint_calculator_address : felt) -> ():
    Ownable_only_owner()
    with_attr error_message("invalid token address"):
        assert_not_zero(lp_token)
    end
    with_attr error_message("invalid oracle address"):
        assert_not_zero(mint_calculator_address)
    end

    different_than_underlying(lp_token)
    whitelisted_tokens.write(lp_token, mint_calculator_address)
    return ()
end

@external
func remove_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt) -> ():
    Ownable_only_owner()
    whitelisted_tokens.write(lp_token , 0)
    return ()
end

@external
func lp_mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
       lp_token : felt, lp_nft_id : Uint256, assets : Uint256, receiver : felt, deadline : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(receiver)
    with_attr error_message("new deadline should be higher or equal to the old deposit"):
        assert_nn_le(deadline, unlock_time)
    end

    with_attr error_message("new deadline should be higher than current timestamp"):
        assert_lt(current_block_timestamp, deadline)
    end
    
    let (caller_address : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (mint_calculator_address : felt) = whitelisted_tokens.read(lp_token)
    let (is_nft : felt) = IERC165.supportsInterface(lp_token, IERC721_ID)

    if is_nft == FALSE:
        let (success : felt) = IERC20.transferFrom(lp_token, caller_address, address_this, assets)
        assert success = TRUE
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        let (id_is_zero : felt) = uint256_is_zero(lp_nft_id)
        with_attr error_message("invalid token id"):
            assert id_is_zero = FALSE
        end
        IERC721.transferFrom(lp_token, caller_address, address_this, lp_nft_id)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    let (amount_to_mint : Uint256) = get_xzkp_out(lp_token, assets)
    let (token_minted : Uint256) = mint(amount_to_mint, receiver)
    let (current_deposit_amount : Uint256) = deposits.read(receiver, lp_token)
    let (new_deposit_amount : Uint256) = uint256_checked_add(current_deposit_amount, token_minted)
    deposits.write(receiver, lp_token, new_deposit_amount)
    deposit_unlock_time.write(receiver, deadline)

    Deposit_lp.emit(caller_address, receiver, lp_token, assets, token_minted)
    ReentrancyGuard_end()
    return (token_minted)
end

@external
func withdraw_lp_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assetAmount : Uint256, lp_token : felt, lp_nft_id : Uint256, receiver : felt, owner : felt) -> ():
    alloc_locals
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)

    with_attr error_message("timestamp lower than deposit deadline"):
        let (current_block_timestamp : felt) = get_block_timestamp()
        let (unlock_time : felt) = deposit_unlock_time.read(owner)
        assert_nn_le(unlock_time, current_block_timestamp)
    end
    tempvar pedersen_ptr = pedersen_ptr
    
    let (address_this : felt) = get_contract_address()
    let (contract_lp_balance : Uint256) = IERC20.balanceOf(lp_token, address_this)
    let (enought_token_balance : felt) = uint256_le(assetAmount, contract_lp_balance)
    

    if enought_token_balance == FALSE:
        let (amount_to_withdraw : Uint256) = uint256_sub(assetAmount, contract_lp_balance)
        withdraw_from_investment_strategies(lp_token, amount_to_withdraw)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    end

    IERC20.transferFrom(lp_token, owner, address_this, assetAmount)
    let (unserlying_asset : felt) = asset()
    # TODO: calculate users return
    IERC20.transfer(unserlying_asset, receiver, Uint256(0,0))
    ReentrancyGuard_end()
    return ()
end

@external
func set_stake_boost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_boost_value : felt) -> ():
    Ownable_only_owner()
    assert_not_zero(new_boost_value)
    stake_boost.write(new_boost_value)
    return ()
end

#
# Internal
#

func only_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(address : felt) -> ():
    let (res : felt) = whitelisted_tokens.read(address)
    with_attr error_message("token not whitelisted"):
        assert_not_zero(res)
    end
    return ()
end


func different_than_underlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(address : felt) -> ():
    with_attr error_message("underlying token not allow"):
        let (unserlying_asset : felt) = asset()
        assert_not_equal(unserlying_asset, address)
    end
    return ()
end

func withdraw_from_investment_strategies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token_address : felt, amount : Uint256) -> ():
    # TODO: implement
    return ()
end
