%lang starknet
from starkware.cairo.common.uint256 import Uint256

const IERC1155_RECEIVER_ID = 0x4e2312e0
const ON_ERC1155_RECEIVED_SELECTOR = 0xf23a6e61
const ON_BATCH_ERC1155_RECEIVED_SELECTOR = 0xbc197c81

@external
func onERC1155Received(
            operator : felt, _from : felt, id : Uint256, value : Uint256,
            data_len : felt, data : felt*) -> (selector : felt):
    if data_len == 0:
        return (ON_ERC1155_RECEIVED_SELECTOR)
    else:
        return (0)
    end
end

@external
func onERC1155BatchReceived(
        operator : felt, _from : felt, ids_len : felt, ids : Uint256*, 
        values_len : felt, values : Uint256*, data_len : felt, data : felt*)
        -> (selector : felt):
    if data_len == 0:
        return (ON_ERC1155_RECEIVED_SELECTOR)
    else:
        return (0)
    end
end

@external
func supportsInterface(interfaceId : felt) -> (success : felt):
    if interfaceId == IERC1155_RECEIVER_ID:
        return (1)
    else:
        return (0)
    end
end