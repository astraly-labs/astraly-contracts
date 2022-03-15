####################################################################################
# @title InterfaceAll contract
# @dev put all interfaces here
# Interfaces include
# - IZkIDOContract
# @author zkpad
####################################################################################

%lang starknet
from starkware.cairo.common.uint256 import (Uint256)

@contract_interface
namespace IZkIDOContract:
    func get_ido_launch_date() -> (res : felt):
    end

    func claim_allocation(amount: felt, account: felt) -> (res: felt):
    end
end