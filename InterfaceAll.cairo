//###################################################################################
// SPDX-License-Identifier: MIT
// @title InterfaceAll contract
// @dev put all interfaces here
// Interfaces include
// - IZkIDOContract
// - IERC4626
// - ITask
// - IZkIDOFactory
// @author astraly
//###################################################################################

%lang starknet
from starkware.cairo.common.uint256 import Uint256

from openzeppelin.introspection.erc165.IERC165 import IERC165

struct UserInfo {
    amount: Uint256,
    reward_debt: Uint256,
}

struct Purchase_Round {
    time_starts: felt,
    time_ends: felt,
    number_of_purchases: Uint256,
}

struct Registration {
    registration_time_starts: felt,
    registration_time_ends: felt,
    number_of_registrants: Uint256,
}

@contract_interface
namespace IAstralyIDOContract {
    func get_ido_launch_date() -> (res: felt) {
    }

    func register_user(amount: Uint256, account: felt, nb_quest: felt) -> (res: felt) {
    }

    func get_purchase_round() -> (res: Purchase_Round) {
    }

    func get_registration() -> (res: Registration) {
    }

    func calculate_allocation() {
    }
}

@contract_interface
namespace IAccount {
    func isValidSignature(hash: felt, signature_len: felt, signature: felt*) -> (is_valid: felt) {
    }
}

@contract_interface
namespace IAstralyIDOFactory {
    func get_ido_launch_date(id: felt) -> (res: felt) {
    }

    func get_ido_address(id: felt) -> (res: felt) {
    }

    func set_sale_owner_and_token(sale_owner_address: felt, sale_token_address: felt) {
    }

    func is_sale_created_through_factory(sale_address: felt) -> (res: felt) {
    }

    func get_lottery_ticket_contract_address() -> (lottery_ticket_address: felt) {
    }

    func get_random_number_generator_address() -> (random_number_generator_address: felt) {
    }

    func get_payment_token_address() -> (payment_token_address: felt) {
    }

    func get_merkle_root(id: felt) -> (merkle_root: felt) {
    }

    func create_ido(ido_admin: felt) -> (new_ido_contract_address: felt) {
    }

    func get_ido_contract_class_hash() -> (class_hash: felt) {
    }

    func set_ido_contract_class_hash(new_class_hash: felt) {
    }
}

@contract_interface
namespace IERC1155_Receiver {
    func onERC1155Received(
        operator: felt, _from: felt, id: Uint256, value: Uint256, data_len: felt, data: felt*
    ) -> (selector: felt) {
    }

    func onERC1155BatchReceived(
        operator: felt,
        _from: felt,
        ids_len: felt,
        ids: Uint256*,
        values_len: felt,
        values: Uint256*,
        data_len: felt,
        data: felt*,
    ) -> (selector: felt) {
    }

    func supportsInterface(interfaceId: felt) -> (success: felt) {
    }
}

@contract_interface
namespace IAdmin {
    func is_admin(user_address: felt) -> (res: felt) {
    }
}

@contract_interface
namespace IZkStakingVault {
    func redistribute(pool_id: felt, user_address: felt, amount_to_burn: felt) {
    }

    func deposited(pool_id: felt, user_address: felt) -> (res: felt) {
    }

    func set_tokens_unlock_time(pool_id: felt, user_address: felt, token_unlock_time: felt) {
    }
}

@contract_interface
namespace IERC4626 {
    func asset() -> (asset_token_address: felt) {
    }

    func totalAssets() -> (total_managed_assets: Uint256) {
    }

    func convertToShares(assets: Uint256) -> (shares: Uint256) {
    }

    func convertToAssets(shares: Uint256) -> (assets: Uint256) {
    }

    func maxDeposit(receiver: felt) -> (max_assets: Uint256) {
    }

    func previewDeposit(assets: Uint256) -> (shares: Uint256) {
    }

    func deposit(assets: Uint256, receiver: felt) -> (shares: Uint256) {
    }

    func maxMint(receiver: felt) -> (max_shares: Uint256) {
    }

    func previewMint(shares: Uint256) -> (assets: Uint256) {
    }

    func mint(shares: Uint256, receiver: felt) -> (assets: Uint256) {
    }

    func maxWithdraw(owner: felt) -> (max_assets: Uint256) {
    }

    func previewWithdraw(assets: Uint256) -> (shares: Uint256) {
    }

    func withdraw(assets: Uint256, receiver: felt, owner: felt) -> (shares: Uint256) {
    }

    func maxRedeem(owner: felt) -> (max_shares: Uint256) {
    }

    func previewRedeem(shares: Uint256) -> (assets: Uint256) {
    }

    func redeem(shares: Uint256, receiver: felt, owner: felt) -> (assets: Uint256) {
    }
}

@contract_interface
namespace IERC20 {
    func name() -> (name: felt) {
    }

    func symbol() -> (symbol: felt) {
    }

    func decimals() -> (decimals: felt) {
    }

    func totalSupply() -> (totalSupply: Uint256) {
    }

    func balanceOf(account: felt) -> (balance: Uint256) {
    }

    func allowance(owner: felt, spender: felt) -> (remaining: Uint256) {
    }

    func transfer(recipient: felt, amount: Uint256) -> (success: felt) {
    }

    func transferFrom(sender: felt, recipient: felt, amount: Uint256) -> (success: felt) {
    }

    func approve(spender: felt, amount: Uint256) -> (success: felt) {
    }

    func mint(to: felt, tokenId: Uint256) {
    }
}

const XOROSHIRO_ADDR = 0x0236b6c5722c5b5e78c215d72306f642de0424a6b56f699d43c98683bea7460d;

@contract_interface
namespace IXoroshiro {
    func next() -> (rnd: felt) {
    }

    func update_seed(seed: felt) {
    }
}

@contract_interface
namespace ITask {
    // # @notice Called by task automators to see if task needs to be executed.
    // # @dev Do not return other values as keeper behavior is undefined.
    // # @return taskReady Assumes the value 1 if automation is ready to be called and 0 otherwise.
    func probeTask() -> (taskReady: felt) {
    }

    // # @notice Main endpoint for task execution. Task automators call this to execute your task.
    // # @dev This function should not have access restrictions. However, this function could
    // # still be called even if `probeTask` returns 0 and needs to be protected accordingly.
    func executeTask() -> () {
    }

    func setIDOContractAddress(address: felt) -> () {
    }
}

@contract_interface
namespace IVault {
    func feePercent() -> (fee_percent: felt) {
    }

    func lockedProfit() -> (res: Uint256) {
    }

    func harvestDelay() -> (harvest_delay: felt) {
    }

    func harvestWindow() -> (harvest_window: felt) {
    }

    func targetFloatPercent() -> (float_percent: felt) {
    }

    func canHarvest() -> (yes_no: felt) {
    }

    func lastHarvestWindowStart() -> (last_harvest_window_start: felt) {
    }

    func getWithdrawalStack() -> (strategies_len: felt, strategies: felt*) {
    }

    func rewardPerBlock() -> (reward: Uint256) {
    }

    func startBlock() -> (block: felt) {
    }

    func endBlock() -> (block: felt) {
    }

    func lastRewardBlock() -> (block: felt) {
    }

    func accTokenPerShare() -> (res: Uint256) {
    }

    func getMultiplier(_from: felt, _to: felt) -> (multiplier: felt) {
    }

    func userInfo(user: felt) -> (info: UserInfo) {
    }

    func totalFloat() -> (float: Uint256) {
    }

    func harvest(strategies_len: felt, strategies: felt*) {
    }

    func setFeePercent(new_fee_percent: felt) {
    }

    func setHarvestDelay(new_harvest_delay: felt) {
    }

    func setHarvestWindow(new_harvest_window: felt) {
    }

    func setTargetFloatPercent(float_percent: felt) {
    }

    func setHarvestTaskContract(address: felt) {
    }

    func updateRewardPerBlockAndEndBlock(_reward_per_block: Uint256, new_end_block: felt) {
    }

    func initializer(
        name: felt,
        symbol: felt,
        asset_addr: felt,
        owner: felt,
        reward_per_block: Uint256,
        start_reward_block: felt,
        end_reward_block: felt,
    ) {
    }

    func harvestRewards() {
    }

    func calculatePendingRewards(user: felt) -> (rewards: Uint256) {
    }

    func pushToWithdrawalStack(strategy: felt) {
    }

    func popFromWithdrawalStack() {
    }

    func setWithdrawalStack(stack_len: felt, stack: felt*) {
    }

    func replaceWithdrawalStackIndex(index: felt, address: felt) {
    }

    func swapWithdrawalStackIndexes(index1: felt, index2: felt) {
    }
}

@contract_interface
namespace IERC721 {
    func balanceOf(owner: felt) -> (balance: Uint256) {
    }

    func ownerOf(tokenId: Uint256) -> (owner: felt) {
    }

    func safeTransferFrom(from_: felt, to: felt, tokenId: Uint256, data_len: felt, data: felt*) {
    }

    func transferFrom(from_: felt, to: felt, tokenId: Uint256) {
    }

    func approve(approved: felt, tokenId: Uint256) {
    }

    func setApprovalForAll(operator: felt, approved: felt) {
    }

    func getApproved(tokenId: Uint256) -> (approved: felt) {
    }

    func isApprovedForAll(owner: felt, operator: felt) -> (isApproved: felt) {
    }

    func mint(to: felt, amount: Uint256) {
    }
}
