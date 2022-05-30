####################################################################################
# SPDX-License-Identifier: MIT
# @title InterfaceAll contract
# @dev put all interfaces here
# Interfaces include
# - IZkIDOContract
# - IERC4626
# @author zkpad
####################################################################################

%lang starknet
from starkware.cairo.common.uint256 import Uint256

struct UserInfo:
    member amount : Uint256
    member reward_debt : Uint256
end

struct Purchase_Round:
    member time_starts : felt
    member time_ends : felt
    member number_of_purchases : Uint256
end

struct Registration:
    member registration_time_starts : felt
    member registration_time_ends : felt
    member number_of_registrants : Uint256
end

@contract_interface
namespace IAccount:
    func is_valid_signature(hash : felt, sig_len : felt, sig : felt*) -> ():
    end
end

@contract_interface
namespace IZkPadIDOContract:
    func get_ido_launch_date() -> (res : felt):
    end

    func register_user(amount : Uint256, account : felt) -> (res : felt):
    end
end

@contract_interface
namespace IZKPadIDOFactory:
    func get_ido_launch_date(id : felt) -> (res : felt):
    end

    func get_ido_address(id : felt) -> (res : felt):
    end
end

@contract_interface
namespace IERC1155_Receiver:
    func onERC1155Received(
        operator : felt, _from : felt, id : Uint256, value : Uint256, data_len : felt, data : felt*
    ) -> (selector : felt):
    end

    func onERC1155BatchReceived(
        operator : felt,
        _from : felt,
        ids_len : felt,
        ids : Uint256*,
        values_len : felt,
        values : Uint256*,
        data_len : felt,
        data : felt*,
    ) -> (selector : felt):
    end

    func supportsInterface(interfaceId : felt) -> (success : felt):
    end
end

@contract_interface
namespace IERC4626:
    func asset() -> (asset_token_address : felt):
    end

    func totalAssets() -> (total_managed_assets : Uint256):
    end

    func convertToShares(assets : Uint256) -> (shares : Uint256):
    end

    func convertToAssets(shares : Uint256) -> (assets : Uint256):
    end

    func maxDeposit(receiver : felt) -> (max_assets : Uint256):
    end

    func previewDeposit(assets : Uint256) -> (shares : Uint256):
    end

    func deposit(assets : Uint256, receiver : felt) -> (shares : Uint256):
    end

    func maxMint(receiver : felt) -> (max_shares : Uint256):
    end

    func previewMint(shares : Uint256) -> (assets : Uint256):
    end

    func mint(shares : Uint256, receiver : felt) -> (assets : Uint256):
    end

    func maxWithdraw(owner : felt) -> (max_assets : Uint256):
    end

    func previewWithdraw(assets : Uint256) -> (shares : Uint256):
    end

    func withdraw(assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    end

    func maxRedeem(owner : felt) -> (max_shares : Uint256):
    end

    func previewRedeem(shares : Uint256) -> (assets : Uint256):
    end

    func redeem(shares : Uint256, receiver : felt, owner : felt) -> (assets : Uint256):
    end
end

@contract_interface
namespace IERC20:
    func name() -> (name : felt):
    end

    func symbol() -> (symbol : felt):
    end

    func decimals() -> (decimals : felt):
    end

    func totalSupply() -> (totalSupply : Uint256):
    end

    func balanceOf(account : felt) -> (balance : Uint256):
    end

    func mint(to : felt, amount : Uint256):
    end

    func allowance(owner : felt, spender : felt) -> (remaining : Uint256):
    end

    func transfer(recipient : felt, amount : Uint256) -> (success : felt):
    end

    func transferFrom(sender : felt, recipient : felt, amount : Uint256) -> (success : felt):
    end

    func approve(spender : felt, amount : Uint256) -> (success : felt):
    end
end

@contract_interface
namespace IVault:
    func feePercent() -> (fee_percent : felt):
    end

    func lockedProfit() -> (res : Uint256):
    end

    func harvestDelay() -> (harvest_delay : felt):
    end

    func harvestWindow() -> (harvest_window : felt):
    end

    func targetFloatPercent() -> (float_percent : felt):
    end

    func canHarvest() -> (yes_no : felt):
    end

    func lastHarvestWindowStart() -> (last_harvest_window_start : felt):
    end

    func getWithdrawalStack() -> (strategies_len : felt, strategies : felt*):
    end

    func rewardPerBlock() -> (reward : Uint256):
    end

    func startBlock() -> (block : felt):
    end

    func endBlock() -> (block : felt):
    end

    func lastRewardBlock() -> (block : felt):
    end

    func accTokenPerShare() -> (res : Uint256):
    end

    func getMultiplier(_from : felt, _to : felt) -> (multiplier : felt):
    end

    func userInfo(user : felt) -> (info : UserInfo):
    end

    func totalFloat() -> (float : Uint256):
    end

    func harvest(strategies_len : felt, strategies : felt*):
    end

    func setFeePercent(new_fee_percent : felt):
    end

    func setHarvestDelay(new_harvest_delay : felt):
    end

    func setHarvestWindow(new_harvest_window : felt):
    end

    func setTargetFloatPercent(float_percent : felt):
    end

    func setHarvestTaskContract(address : felt):
    end

    func updateRewardPerBlockAndEndBlock(reward_per_block : Uint256, new_end_block : felt):
    end

    func initializer(
        name : felt,
        symbol : felt,
        asset_addr : felt,
        owner : felt,
        reward_per_block : Uint256,
        start_reward_block : felt,
        end_reward_block : felt,
    ):
    end

    func harvestRewards():
    end

    func calculatePendingRewards(user : felt) -> (rewards : Uint256):
    end

    func pushToWithdrawalStack(strategy : felt):
    end

    func popFromWithdrawalStack():
    end

    func setWithdrawalStack(stack_len : felt, stack : felt*):
    end

    func replaceWithdrawalStackIndex(index : felt, address : felt):
    end

    func swapWithdrawalStackIndexes(index1 : felt, index2 : felt):
    end
end
