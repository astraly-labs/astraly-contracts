%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.token.erc20.library import (
    ERC20_name,
    ERC20_symbol,
    ERC20_totalSupply,
    ERC20_decimals,
    ERC20_balanceOf,
    ERC20_allowance,
    ERC20_initializer,
    ERC20_approve,
    ERC20_transfer,
    ERC20_transferFrom,
    ERC20_mint,
    ERC20_burn,
)

from openzeppelin.utils.constants import TRUE

from contracts.erc4626.library import (
    ERC4626_initializer,
    ERC4626_asset,
    ERC4626_totalAssets,
    ERC4626_convertToShares,
    ERC4626_convertToAssets,
    ERC4626_maxDeposit,
    ERC4626_previewDeposit,
    ERC4626_deposit,
    ERC4626_maxMint,
    ERC4626_previewMint,
    ERC4626_mint,
    ERC4626_maxWithdraw,
    ERC4626_previewWithdraw,
    ERC4626_withdraw,
    ERC4626_maxRedeem,
    ERC4626_previewRedeem,
    ERC4626_redeem,
    decrease_allowance_by_amount,
    set_default_lock_time,
    days_to_seconds,
    default_lock_time_days,
    last_harvest,
    last_harvest_window_start,
)

#
# ERC 20
#

#
# Getters
#

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC20_name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC20_symbol()
    return (symbol)
end

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalSupply : Uint256
):
    let (totalSupply : Uint256) = ERC20_totalSupply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    decimals : felt
):
    let (decimals) = ERC20_decimals()
    return (decimals)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (balance : Uint256):
    let (balance : Uint256) = ERC20_balanceOf(account)
    return (balance)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining : Uint256) = ERC20_allowance(owner, spender)
    return (remaining)
end

# @notice Calculates the total amount of underlying tokens the Vault holds.
# @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
@view
func totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalManagedAssets : Uint256
):
    let (totalManagedAssets : Uint256) = ERC4626_totalAssets()
    return (totalManagedAssets)
end

#
# ERC 4626
#

@view
func asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    assetTokenAddress : felt
):
    let (asset : felt) = ERC4626_asset()
    return (asset)
end

@view
func convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    let (shares : Uint256) = ERC4626_convertToShares(assets)
    return (shares)
end

@view
func convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (assets : Uint256) = ERC4626_convertToAssets(shares)
    return (assets)
end

@view
func maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    receiver : felt
) -> (maxAssets : Uint256):
    let (maxAssets : Uint256) = ERC4626_maxDeposit(receiver)
    return (maxAssets)
end

@view
func maxMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    receiver : felt
) -> (maxShares : Uint256):
    let (maxShares : Uint256) = ERC4626_maxMint(receiver)
    return (maxShares)
end

@view
func maxWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt
) -> (maxAssets : Uint256):
    let (maxWithdraw : Uint256) = ERC4626_maxWithdraw(owner)
    return (maxWithdraw)
end

@view
func previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    let (shares : Uint256) = ERC4626_previewWithdraw(assets)
    return (shares)
end

@view
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    let (default_lock_period : felt) = default_lock_time_days.read()
    let (shares) = ERC4626_previewDeposit(assets, default_lock_period)
    return (shares)
end

@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (default_lock_period : felt) = default_lock_time_days.read()
    let (assets) = ERC4626_previewMint(shares, default_lock_period)
    return (assets)
end

@view
func previewMintForTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (assets : Uint256):
    let (assets) = ERC4626_previewMint(shares, lock_time)
    return (assets)
end

@view
func maxRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt) -> (
    maxShares : Uint256
):
    let (maxShares : Uint256) = ERC4626_maxRedeem(owner)
    return (maxShares)
end

@view
func previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (assets : Uint256) = ERC4626_previewRedeem(shares)
    return (assets)
end
