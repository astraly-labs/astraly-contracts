%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import Uint256
from starkware.starknet.common.syscalls import deploy
from starkware.starknet.common.syscalls import get_contract_address

from openzeppelin.security.initializable.library import Initializable

from contracts.ZkPadAccessControl import ZkPadAccessControl


@storage_var
func SBT_badge_class_hash() -> (hash : felt):
end

@event
func SBTContractCreated(contract_address : felt,
    lock_number : felt, balance : Uint256, token_address : felt):
end

@event
func SBTClassHashChanged(new_class_hash : felt):
end

@external
func initialize{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    _SBT_badge_class_hash : felt, admin_address : felt
):
    with_attr error_message("Class hash cannot be zero"):
        assert_not_zero(_SBT_badge_class_hash)
    end

    with_attr error_message("Invalid admin address"):
        assert_not_zero(admin_address)
    end

    Initializable.initialize()
    ZkPadAccessControl.initializer(admin_address)
    SBT_badge_class_hash.write(_SBT_badge_class_hash)
    return ()
end

@external
func setSBTBadgeClassHash{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(new_class_hash : felt):
    ZkPadAccessControl.assert_only_owner()

    with_attr error_message("Invalid new class hash"):
        assert_not_zero(new_class_hash)
    end

    SBT_badge_class_hash.write(new_class_hash)
    SBTClassHashChanged.emit(new_class_hash)
    return()
end

# token_address can be 0 in case of eth
@external
func createSBTContract{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    block_number : felt, balance : Uint256, token_address : felt):
    ZkPadAccessControl.assert_only_owner()

    assert_not_zero(block_number)
    let (class_hash : felt) = SBT_badge_class_hash.read()
    let (salt : felt) = get_contract_address()

    let (new_SBT_badge_contract_address : felt) = deploy(
        class_hash=class_hash,
        contract_address_salt=salt,
        constructor_calldata_size=4,
        constructor_calldata=cast(new (block_number, balance, token_address), felt*),
        deploy_from_zero=0
    )
    SBTContractCreated.emit(new_SBT_badge_contract_address, block_number, balance, token_address)
    return ()
end
