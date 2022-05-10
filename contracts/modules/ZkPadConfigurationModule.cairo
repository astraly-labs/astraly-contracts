%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_equal, assert_not_zero
from starkware.starknet.common.syscalls import get_caller_address

from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner
from contracts.ZkPadStaking import IVault

@contract_interface
namespace IConfigurationModule:
    func syncFeePercent(vault : felt):
    end
    
    func syncHarvestDelay(vault : felt):
    end
    
    func syncHarvestWindow(vault : felt):
    end

    func syncTargetFloatPercent(vault : felt):
    end
end

################################################################
#                             Events
################################################################
# @notice Emitted when the default fee percentage is updated.
# @param new_default_fee_percent The new default fee percentage.
@event
func DefaultFeePercentUpdated(new_default_fee_percent : felt):
end

# @notice Emitted when the default harvest delay is updated.
# @param new_default_harvest_Delay The new default harvest delay.
@event
func DefaultHarvestDelayUpdated(new_default_harvest_Delay : felt):
end

# @notice Emitted when the default harvest window is updated.
# @param new_default_harvest_window The new default harvest window.
@event
func DefaultHarvestWindowUpdated(new_default_harvest_window : felt):
end

# @notice Emitted when the default target float percentage is updated.
# @param new_default_target_float_percent The new default target float percentage.
@event
func DefaultTargetFloatPercentUpdated(new_default_target_float_percent : felt):
end

# @notice Emitted when a Vault has its custom fee percentage set/updated.
# @param vault The Vault that had its custom fee percentage set/updated.
# @param new_custom_fee_percent The new custom fee percentage for the Vault.
@event
func CustomFeePercentUpdated(vault : felt, new_custom_fee_percent : felt):
end

# @notice Emitted when a Vault has its custom harvest delay set/updated.
# @param vault The Vault that had its custom harvest delay set/updated.
# @param new_custom_harvest_delay The new custom harvest delay for the Vault.
@event 
func CustomHarvestDelayUpdated(vault : felt, new_custom_harvest_delay : felt):
end

# @notice Emitted when a Vault has its custom harvest window set/updated.
# @param vault The Vault that had its custom harvest window set/updated.
# @param new_custom_harvest_window The new custom harvest window for the Vault.
@event
func CustomHarvestWindowUpdated(vault : felt, new_custom_harvest_window : felt):
end

# @notice Emitted when a Vault has its custom target float percentage set/updated.
# @param vault The Vault that had its custom target float percentage set/updated.
# @param new_custom_target_float_percent The new custom target float percentage for the Vault.
@event 
func CustomTargetFloatPercentUpdated(vault : felt, new_custom_target_float_percent : felt):
end


################################################################
#                             Storage variables
################################################################

# @notice The default fee percentage for Vaults.
# @dev See the documentation for the feePercentage
# variable in the Vault contract for more details.
@storage_var
func default_fee_percent() -> (fee_percent : felt):
end

# @notice The default harvest delay for Vaults.
# @dev See the documentation for the harvestDelay
# variable in the Vault contract for more details.
@storage_var
func default_harvest_delay() -> (harvest_delay : felt):
end

# @notice The default harvest window for Vaults.
# @dev See the documentation for the harvestWindow
# variable in the Vault contract for more details.
@storage_var
func default_harvest_window() -> (harvest_window : felt):
end

# @notice The default target float percentage for Vaults.
# @dev See the documentation for the targetFloatPercent
# variable in the Vault contract for more details.
@storage_var
func default_target_float_percent() -> (target_float_percent : felt):
end

#####
# Mappings
#####
# @notice Maps Vaults to their custom fee percentage.
# @dev Will be 0 if there is no custom fee percentage for the Vault.
# @dev See the documentation for the targetFloatPercent variable in the Vault contract for more details.
@storage_var
func vault_custom_fee_percent(vault : felt) -> (fee_percent : felt):
end

# @notice Maps Vaults to their custom harvest delay.
# @dev Will be 0 if there is no custom harvest delay for the Vault.
# @dev See the documentation for the harvestDelay variable in the Vault contract for more details.
@storage_var
func vault_custom_harvest_delay(vault : felt) -> (harvest_delay : felt):
end

# @notice Maps Vaults to their custom harvest window.
# @dev Will be 0 if there is no custom harvest window for the Vault.
# @dev See the documentation for the harvestWindow variable in the Vault contract for more details.
@storage_var
func vault_custom_harvest_window(vault : felt) -> (harvest_window : felt):
end

# @notice Maps Vaults to their custom target float percentage.
# @dev Will be 0 if there is no custom target float percentage for the Vault.
# @dev See the documentation for the targetFloatPercent variable in the Vault contract for more details.
@storage_var
func vault_custom_target_float_percent(vault : felt) -> (target_float_percent : felt):
end


@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt):
    assert_not_zero(owner)
    Ownable_initializer(owner)
    return ()
end

################################################################
#                             Getters
################################################################
@view
func defaultFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (fee_percent : felt):
    let (fee_percent : felt) = default_fee_percent.read()
    return (fee_percent)
end

@view
func defaultHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (harvest_delay : felt):
    let (harvest_delay : felt) = default_harvest_delay.read()
    return (harvest_delay)
end

@view
func defaultHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (harvest_window : felt):
    let (harvest_window : felt) = default_harvest_window.read()
    return (harvest_window)
end

@view
func defaultTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (target_float_percent : felt):
    let (target_float_percent : felt) = default_target_float_percent.read()
    return (target_float_percent)
end

@view
func getVaultCustomFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt) -> (fee_percent : felt):
    let (res : felt) = vault_custom_fee_percent.read(vault)
    return (res)
end

@view
func getVaultCustomHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt) -> (harvest_delay : felt):
    let (res : felt) = vault_custom_harvest_delay.read(vault)
    return (res)
end

@view
func getVaultCustomHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt) -> (harvest_window : felt):
    let (res : felt) = vault_custom_harvest_window.read(vault)
    return (res)
end

@view
func getVaultCustomTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt) -> (target_float_percent : felt):
    let (res : felt) = vault_custom_target_float_percent.read(vault)
    return (res)
end

################################################################
#                             Setters
################################################################
@external
func setDefaultFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_fee_percent : felt):
    Ownable_only_owner()
    default_fee_percent.write(new_fee_percent)
    DefaultFeePercentUpdated.emit(new_fee_percent)
    return ()
end

@external
func setDefaultHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_harvest_delay : felt):
    Ownable_only_owner()
    default_harvest_delay.write(new_harvest_delay)
    DefaultHarvestDelayUpdated.emit(new_harvest_delay)
    return ()
end

@external
func setDefaultHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_harvest_window : felt):
    Ownable_only_owner()
    default_harvest_window.write(new_harvest_window)
    DefaultHarvestWindowUpdated.emit(new_harvest_window)
    return ()
end

@external
func setDefaultTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_target_float_percent : felt):
    Ownable_only_owner()
    default_target_float_percent.write(new_target_float_percent)
    DefaultTargetFloatPercentUpdated.emit(new_target_float_percent)
    return ()
end

@external
func setVaultCustomFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt, new_custom_fee_percent : felt):
    Ownable_only_owner()
    vault_custom_fee_percent.write(vault, new_custom_fee_percent)
    CustomFeePercentUpdated.emit(vault, new_custom_fee_percent)
    return ()
end

@external
func setVaultCustomHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt, new_custom_harvest_delay : felt):
    Ownable_only_owner()
    vault_custom_harvest_delay.write(vault, new_custom_harvest_delay)
    CustomHarvestDelayUpdated.emit(vault, new_custom_harvest_delay)
    return ()
end

@external
func setVaultCustomHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt, new_custom_harvest_window : felt):
    Ownable_only_owner()
    vault_custom_harvest_window.write(vault, new_custom_harvest_window)
    CustomHarvestWindowUpdated.emit(vault, new_custom_harvest_window)
    return ()
end

@external
func setVaultCustomTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt, new_custom_target_float_percent : felt):
    Ownable_only_owner()
    vault_custom_target_float_percent.write(vault, new_custom_target_float_percent)
    CustomTargetFloatPercentUpdated.emit(vault, new_custom_target_float_percent)
    return ()
end


####### VAULT PARAMETER SYNC LOGIC

# @notice Syncs a Vault's fee percentage with either the Vault's custom fee
# percentage or the default fee percentage if a custom percentage is not set.
# @param vault The Vault to sync the fee percentage for.
@external
func syncFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt):
    alloc_locals
    let (custom_fee_percent : felt) = getVaultCustomFeePercent(vault)
    tempvar new_fee_percent
    if custom_fee_percent == 0:
        let (current_default_fee_percent : felt) = defaultFeePercent()
        new_fee_percent = current_default_fee_percent
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        new_fee_percent = custom_fee_percent
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    end

    let (current_vault_fee_percent : felt) = IVault.feePercent(vault)
    with_attr error_message("ALREADY_SYNCED"):
        assert_not_equal(current_vault_fee_percent, new_fee_percent)
    end

    IVault.setFeePercent(vault, new_fee_percent)
    return ()
end

@external
func syncHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt):
    alloc_locals
    let (custom_harvest_delay : felt) = getVaultCustomHarvestDelay(vault)
    tempvar new_harvest_delay
    if custom_harvest_delay == 0:
        let (current_default_harvest_delay : felt) = defaultHarvestDelay()
        new_harvest_delay = current_default_harvest_delay
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        new_harvest_delay = custom_harvest_delay
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    end

    let (current_vault_harvest_delay : felt) = IVault.harvestDelay(vault)
    with_attr error_message("ALREADY_SYNCED"):
        assert_not_equal(current_vault_harvest_delay, new_harvest_delay)
    end

    IVault.setHarvestDelay(vault, new_harvest_delay)
    return ()
end

@external
func syncHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt):
    alloc_locals
    let (custom_harvest_window : felt) = getVaultCustomHarvestWindow(vault)
    tempvar new_harvest_window
    if custom_harvest_window == 0:
        let (current_default_harvest_window : felt) = defaultHarvestWindow()
        new_harvest_window = current_default_harvest_window
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        new_harvest_window = custom_harvest_window
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    end

    let (current_vault_harvest_window : felt) = IVault.harvestWindow(vault)
    with_attr error_message("ALREADY_SYNCED"):
        assert_not_equal(current_vault_harvest_window, new_harvest_window)
    end

    IVault.setHarvestWindow(vault, new_harvest_window)
    return ()
end

@external
func syncTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt):
    alloc_locals
    let (custom_target_float_percent : felt) = getVaultCustomTargetFloatPercent(vault)
    tempvar new_target_float_percent
    if custom_target_float_percent == 0:
        let (current_default_target_float_percent : felt) = defaultTargetFloatPercent()
        new_target_float_percent = current_default_target_float_percent
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    else:
        new_target_float_percent = custom_target_float_percent
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr = pedersen_ptr
    end

    let (current_target_float_percent : felt) = IVault.targetFloatPercent(vault)
    with_attr error_message("ALREADY_SYNCED"):
        assert_not_equal(current_target_float_percent, new_target_float_percent)
    end

    IVault.setTargetFloatPercent(vault, new_target_float_percent)
    return ()
end
