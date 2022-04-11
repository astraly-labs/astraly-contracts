# SPDX-License-Identifier: MIT
# https://github.com/koloz193/ERC4626 2af813d
%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256

from contracts.erc4626.library import ERC4626

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        name : felt, symbol : felt, decimals : felt, asset : felt):
    ERC4626.initialize(name, symbol, decimals, asset)
    return ()
end

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC4626.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC4626.symbol()
    return (symbol)
end

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalSupply : Uint256):
    let (totalSupply) = ERC4626.totalSupply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        decimals : felt):
    let (decimals) = ERC4626.decimals()
    return (decimals)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        account : felt) -> (balance : Uint256):
    let (balance : Uint256) = ERC4626.balanceOf(account)
    return (balance)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt, spender : felt) -> (allowance : Uint256):
    let (allowance) = ERC4626.allowance(owner, spender)
    return (allowance)
end

@view
func asset{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (asset : felt):
    let (asset) = ERC4626.asset()
    return (asset)
end

@view
func totalAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        totalAssets : Uint256):
    let (totalAssets : Uint256) = ERC4626.totalAssets()
    return (totalAssets)
end

@view
func convertToAssets{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shareAmount : Uint256) -> (assetAmount : Uint256):
    let (assetAmount : Uint256) = ERC4626.convertToAssets(shareAmount)
    return (assetAmount)
end

@view
func convertToShares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assetAmount : Uint256) -> (shareAmount : Uint256):
    let (shareAmount : Uint256) = ERC4626.convertToShares(assetAmount)
    return (shareAmount)
end

@view
func maxDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        maxAmount : Uint256):
    let (maxAmount) = ERC4626.maxDeposit()
    return (maxAmount)
end

@view
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assetAmount : Uint256) -> (shareAmount : Uint256):
    let (shareAmount) = ERC4626.previewDeposit(assetAmount)
    return (shareAmount)
end

@view
func maxMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt) -> (
        maxAmount : Uint256):
    let (maxAmount) = ERC4626.maxMint(owner)
    return (maxAmount)
end

@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shareAmount : Uint256) -> (assetAmount : Uint256):
    let (asset_amount) = ERC4626.previewMint(shareAmount)
    return (asset_amount)
end

@view
func maxWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        owner : felt) -> (maxAmount : Uint256):
    let (maxAmount) = ERC4626.maxWithdraw(owner)
    return (maxAmount)
end

@view
func previewWithdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assetAmount : Uint256) -> (shareAmount : Uint256):
    let (shareAmount) = ERC4626.previewWithdraw(assetAmount)
    return (shareAmount)
end

@view
func maxRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt) -> (
        maxAmount : Uint256):
    alloc_locals
    local uint_max_high = 2 ** 128 - 1
    local uint_max_low = 2 ** 128
    let maxAmount = Uint256(low=uint_max_low, high=uint_max_high)
    return (maxAmount)
end

@view
func previewRedeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shareAmount : Uint256) -> (assetAmount : Uint256):
    let (asset_amount) = ERC4626.previewRedeem(shareAmount)
    return (asset_amount)
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        receiver : felt, amount : Uint256) -> (success : felt):
    let (success) = ERC4626.transfer(receiver, amount)
    return (success)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        sender : felt, receiver : felt, amount : Uint256) -> (success : felt):
    let (success) = ERC4626.transferFrom(sender, receiver, amount)
    return (success)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        spender : felt, amount : Uint256) -> (success : felt):
    let (success) = ERC4626.approve(spender, amount)
    return (success)
end

@external
func increaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        spender : felt, added_value : Uint256) -> (success : felt):
    let (success) = ERC4626.increaseAllowance(spender, added_value)
    return (success)
end

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        spender : felt, subtracted_value : Uint256) -> (success : felt):
    let (success) = ERC4626.decreaseAllowance(spender, subtracted_value)
    return (success)
end

@external
func deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assetAmount : Uint256, receiver : felt) -> (shareAmount : Uint256):
    let (share_amount) = ERC4626.deposit(assetAmount, receiver)
    return (share_amount)
end

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shareAmount : Uint256, receiver : felt) -> (assetAmount : Uint256):
    let (asset_amount) = ERC4626.mint(shareAmount, receiver)
    return (asset_amount)
end

@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        assetAmount : Uint256, receiver : felt, owner : felt) -> (shareAmount : Uint256):
    let (share_amount) = ERC4626.withdraw(assetAmount, receiver, owner)
    return (share_amount)
end

@external
func redeem{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        shareAmount : Uint256, receiver : felt, owner : felt) -> (assetAmount : Uint256):
    let (asset_amount) = ERC4626.redeem(shareAmount, receiver, owner)
    return (asset_amount)
end
