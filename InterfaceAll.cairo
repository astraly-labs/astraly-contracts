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

@contract_interface
namespace IERC20:
    func name() -> (name: felt):
    end

    func symbol() -> (symbol: felt):
    end

    func decimals() -> (decimals: felt):
    end

    func totalSupply() -> (totalSupply: Uint256):
    end

    func balanceOf(account: felt) -> (balance: Uint256):
    end

    func allowance(owner: felt, spender: felt) -> (remaining: Uint256):
    end

    func transfer(recipient: felt, amount: Uint256) -> (success: felt):
    end

    func transferFrom(
            sender: felt, 
            recipient: felt, 
            amount: Uint256
        ) -> (success: felt):
    end

    func approve(spender: felt, amount: Uint256) -> (success: felt):
    end
end

@contract_interface
namespace IAdmin:
    func is_admin(user_address : felt) -> (res : felt):
    end
end

@contract_interface
namespace IZkIDOFactory:
    func set_sale_owner_and_token(sale_owner_address : felt, sale_token_address : felt):
    end

    func is_sale_created_through_factory(sale_address : felt) -> (res : felt):
    end
end

@contract_interface
namespace IZkStakingVault:
    func redistribute(
        pool_id : felt, 
        user_address : felt,
        amount_to_burn : felt):
    end

    func deposited(pool_id : felt, user_address : felt) -> (res : felt):
    end

    func set_tokens_unlock_time(
        pool_id : felt,
        user_address : felt,
        token_unlock_time : felt
    ):
    end
end

