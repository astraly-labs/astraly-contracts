%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_equal, assert_not_zero
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address

from openzeppelin.utils.constants import TRUE, FALSE
from openzeppelin.access.ownable import (Ownable_only_owner)
from openzeppelin.introspection.IERC165 import IERC165
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721

from contracts.openzeppelin.security.reentrancy_guard import ReentrancyGuard_start, ReentrancyGuard_end
from contracts.erc4626.ERC4626 import (
    name, symbol, totalSupply, decimals, balanceOf, allowance,
    transfer, transferFrom, approve,
    asset, totalAssets, convertToShares, convertToAssets, maxDeposit, previewDeposit,
    deposit, maxMint, previewMint, mint, maxWithdraw, previewWithdraw, withdraw,
    maxRedeem, previewRedeem, redeem)
from contracts.erc4626.library import uint256_is_zero

const IERC721_ID = 0x80ac58cd

@contract_interface
namespace IMintCalculator:
    func get_amount_to_mint(input : Uint256) -> (amount : Uint256):
    end
end


@storage_var
func whitelisted_tokens(lp_token : felt) -> (mint_calculator_address : felt):
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
func get_xzkp_out{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt, amount : Uint256) -> (res : Uint256):
    let (mint_calculator_address : felt) = whitelisted_tokens.read(lp_token)
    with_attr error_message("invalid oracle address"):
        assert_not_zero(mint_calculator_address)
    end
    let (res : Uint256) = IMintCalculator.get_amount_to_mint(mint_calculator_address, amount)
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
    whitelisted_tokens.write(lp_token , mint_calculator_address)
    return ()
end

@external
func remove_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt) -> ():
    Ownable_only_owner()
    whitelisted_tokens.write(lp_token , 0)
    return ()
end

@external
func deposit_lp{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
       lp_token : felt, lp_nft_id : Uint256, assets : Uint256, receiver : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)

    let (caller_address : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()

    let (mint_calculator_address : felt) = whitelisted_tokens.read(lp_token)
    let (is_nft : felt) = IERC165.supportsInterface(lp_token, IERC721_ID)
    if is_nft == FALSE:
        let (success : felt) = IERC20.transferFrom(lp_token, caller_address, address_this, assets)
        assert success = TRUE
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        let (amount_to_mint : Uint256) = IMintCalculator.get_amount_to_mint(mint_calculator_address, lp_nft_id)
    else:
        let (id_is_zero : felt) = uint256_is_zero(lp_nft_id)
        with_attr error_message("invalid token id"):
            assert id_is_zero = FALSE
        end
        IERC721.transferFrom(lp_token, caller_address, address_this, lp_nft_id)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        let (amount_to_mint : Uint256) = IMintCalculator.get_amount_to_mint(mint_calculator_address, assets)
    end

    
    let (token_minted : Uint256) = mint(amount_to_mint, receiver)
    ReentrancyGuard_end()
    return (token_minted)
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
