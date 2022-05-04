%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IARFPoolFactory:
    func getFactory() -> (factory_address: felt):
    end

    func quote(
        amount_token_0: Uint256, 
        reserve_token_0: Uint256, 
        reserve_token_1: Uint256) 
        -> (amount_token_0: Uint256):
    end

    func removeLiquidityQuote(
        amount_lp: Uint256, 
        reserve_token_0: Uint256, 
        reserve_token_1: Uint256, 
        total_supply: Uint256) 
        -> (amount_token_0: Uint256, amount_token_1: Uint256):
    end

    func removeLiquidityQuoteByPool(
        amount_lp: Uint256, 
        pool_address: felt) 
        -> (token_0_address: felt, token_1_address: felt, amount_token_0: Uint256, amount_token_1: Uint256):
    end

    func addLiquidity(
        token_0_address: felt, 
        token_1_address: felt, 
        amount_0_desired: Uint256, 
        amount_1_desired: Uint256,
        amount_0_min: Uint256, 
        amount_1_min: Uint256) 
        -> (liquidity_minted: Uint256):
    end

    func removeLiquidity(
        token_0_address: felt, 
        token_1_address: felt, 
        amount_token_0_min: Uint256, 
        amount_token_1_min: Uint256,
        liquidity: Uint256) 
        -> (amount_token_0: Uint256, amount_token_1: Uint256):
    end

    func swapExactTokensForTokens(
        token_from_address: felt,
        token_to_address: felt,
        amount_token_from: Uint256,
        amount_token_to_min: Uint256) 
        -> (amount_out_received: Uint256):
    end

    func swapTokensForExactTokens(
        token_from_address: felt,
        token_to_address: felt,
        amount_token_to: Uint256,
        amount_token_from_max: Uint256) 
        -> (amount_out_received: Uint256):
    end

    func updateFactory(new_factory_address: felt) -> (success: felt):
    end
end

@contract_interface
namespace IARFPool:
    func name() -> (name: felt):
    end

    func symbol() -> (symbol: felt):
    end

    func decimals() -> (decimals: felt):
    end

    func totalSupply() -> (total_supply: Uint256):
    end

    func balanceOf(account: felt) -> (balance: Uint256):
    end

    func allowance(owner_address: felt, spender_address: felt) -> (remaining: Uint256):
    end

    func getToken0() -> (token_address: felt):
    end

    func getToken1() -> (token_address: felt):
    end

    func getReserves() -> (reserve_token_0: Uint256, reserve_token_1: Uint256):
    end

    func getBatchInfos() -> (name: felt, symbol: felt, decimals: felt, total_supply: Uint256, token_0_address: felt, token_1_address: felt, reserve_token_0: Uint256, reserve_token_1: Uint256):
    end

    func transfer(recipient_address: felt, amount: Uint256) -> (success: felt):
    end
 
    func transferFrom(
            sender_address: felt, 
            recipient_address: felt, 
            amount: Uint256
        ) -> (success: felt):
    end

    func approve(spender_address: felt, amount: Uint256) -> (success: felt):
    end

    func mint(to_address: felt) -> (liquidity_minted: Uint256):
    end

    func burn(to_address: felt) -> (amount_token_0: Uint256, amount_token_1: Uint256):
    end

    func swap(amount_out_token_0: Uint256, amount_out_token_1: Uint256, recipient_address: felt) -> (amount_out_received: Uint256):
    end
end
