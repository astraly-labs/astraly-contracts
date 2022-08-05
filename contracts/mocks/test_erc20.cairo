%lang starknet

from openzeppelin.token.erc20.presets.ERC20Mintable import constructor

@external
func supportsInterface(interfaceId : felt) -> (success : felt):
    return (0)
end
