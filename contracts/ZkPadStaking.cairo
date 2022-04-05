%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_equal, assert_not_zero

from contracts.openzeppelin.utils.constants import TRUE, FALSE, IERC721_ID
from contracts.openzeppelin.access.ownable import (Ownable_only_owner)
from contracts.openzeppelin.introspection.IERC165 import IERC165
from contracts.openzeppelin.security.reentrancy_guard import ReentrancyGuard_start, ReentrancyGuard_end

from contracts.erc4626.ERC4626 import (
    name, symbol, totalSupply, decimals, balanceOf, allowance,
    transfer, transferFrom, approve,
    asset, totalAssets, convertToShares, convertToAssets, maxDeposit, previewDeposit,
    deposit, maxMint, previewMint, mint, maxWithdraw, previewWithdraw, withdraw,
    maxRedeem, previewRedeem, redeem)


# Chainlink
struct Response:
    member roundId : felt
    member answer : felt
    member startedAt : felt
    member updatedAt : felt
    member answeredInRound : felt
end

@contract_interface
namespace AggregatorV3Interface:
 
    func latestRoundData() -> (res : Response):
    end
end

@storage_var
func whitelisted_tokens(lp_token : felt) -> (aggregator_address : felt):
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
func get_xzkp_out{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt, amount : felt) -> (res : Uint256):
    only_whitelisted_token(lp_token)


    let (res : Uint256) = previewMint(Uint256(0,0))
    return (res)
end


#
# Externals
#

@external
func add_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(lp_token : felt, aggregator_address : felt) -> ():
    Ownable_only_owner()
    assert_not_zero(lp_token)
    assert_not_zero(aggregator_address)
    different_than_underlying(lp_token)
    whitelisted_tokens.write(lp_token , aggregator_address)
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
       lp_token : felt, assets : Uint256, receiver : felt) -> (shares : Uint256):
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)

    let (is_nft : felt) = IERC165.supportsInterface(lp_token, IERC721_ID)
    if is_nft == FALSE:
        
    end
    

    ReentrancyGuard_end()
    return (Uint256(0,0))
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
