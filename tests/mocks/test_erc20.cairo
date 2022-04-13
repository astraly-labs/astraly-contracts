%lang starknet

from openzeppelin.token.erc20.ERC20 import (
    name, symbol, totalSupply, decimals, balanceOf, allowance, transfer, transferFrom, approve,
    increaseAllowance, decreaseAllowance
)


@external
func supportsInterface(interfaceId: felt) -> (success: felt):
    return (0)
end
