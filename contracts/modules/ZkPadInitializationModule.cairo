%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero

from openzeppelin.access.ownable import Ownable_initializer, Ownable_only_owner

from contracts.modules.ZkPadConfigurationModule import IConfigurationModule
from contracts.ZkPadStaking import IVault

################################################################
#                             Events
################################################################
@event
func ConfigModuleUpdated(new_config_module : felt):
end



################################################################
#                             Storage variables
################################################################
@storage_var
func config_module() -> (address : felt):
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(owner : felt, _config_module : felt):
    assert_not_zero(owner)
    assert_not_zero(_config_module)
    Ownable_initializer(owner)
    config_module.write(_config_module)
    return ()
end

################################################################
#                             Getters
################################################################
@view
func configModule{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (res : felt):
    let (res : felt) = config_module.read()
    return (res)
end

####################################################################################
#                                  External Functions
####################################################################################
@external
func setConfigModule{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_config_module : felt):
    Ownable_only_owner()
    config_module.write(new_config_module)
    ConfigModuleUpdated.emit(new_config_module)
    return ()
end

@external
func initializeVault{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(vault : felt):
    assert_not_zero(vault)
    let (config_module_address : felt) = configModule()
    IConfigurationModule.syncFeePercent(config_module_address, vault)
    IConfigurationModule.syncHarvestDelay(config_module_address, vault)
    IConfigurationModule.syncHarvestWindow(config_module_address, vault)
    IConfigurationModule.syncTargetFloatPercent(config_module_address, vault)
    return ()
end
