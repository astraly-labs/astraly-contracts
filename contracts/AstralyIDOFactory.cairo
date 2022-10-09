%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp, deploy

from contracts.AstralyAccessControl import AstralyAccessControl, OWNER_ROLE

from InterfaceAll import IAstralyIDOContract

@storage_var
func ido_contract_addresses(id: felt) -> (address: felt) {
}
@storage_var
func ino_contract_addresses(id: felt) -> (address: felt) {
}

@storage_var
func scorer_addresses(id: felt) -> (address: felt) {
}

@storage_var
func current_id() -> (id: felt) {
}

@storage_var
func random_number_generator_address() -> (res: felt) {
}

@storage_var
func payment_token_address() -> (res: felt) {
}

@storage_var
func merkle_root(id: felt) -> (root: felt) {
}

@storage_var
func ido_contract_class_hash() -> (class_hash: felt) {
}

@storage_var
func ino_contract_class_hash() -> (class_hash: felt) {
}

@event
func IDO_Created(id: felt, address: felt) {
}

@event
func INO_Created(id: felt, address: felt) {
}

@view
func get_ido_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(id: felt) -> (
    address: felt
) {
    alloc_locals;
    let (the_address: felt) = ido_contract_addresses.read(id);

    return (the_address,);
}

@view
func get_ino_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(id: felt) -> (
    address: felt
) {
    alloc_locals;
    let (the_address: felt) = ido_contract_addresses.read(id);

    return (the_address,);
}
@view
func get_random_number_generator_address{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}() -> (res: felt) {
    let (rnd_nbr_gen_adr) = random_number_generator_address.read();
    return (res=rnd_nbr_gen_adr);
}

@view
func get_payment_token_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (payment_token_address: felt) {
    let (pmt_tkn_addr) = payment_token_address.read();
    return (payment_token_address=pmt_tkn_addr);
}

@view
func get_merkle_root{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(id: felt) -> (
    merkle_root: felt
) {
    let (res: felt) = merkle_root.read(id);
    return (merkle_root=res);
}

@view
func get_ido_contract_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (class_hash: felt) {
    let (class_hash: felt) = ido_contract_class_hash.read();
    return (class_hash,);
}
@view
func get_ino_contract_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (class_hash: felt) {
    let (class_hash: felt) = ino_contract_class_hash.read();
    return (class_hash,);
}

@external
func grant_owner_role{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt
) {
    AstralyAccessControl.grant_role(OWNER_ROLE, address);
    return ();
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(owner_: felt) {
    AstralyAccessControl.initializer(owner_);
    return ();
}

@external
func create_ido{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ido_admin: felt, scorer: felt
) -> (new_ido_contract_address: felt) {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();
    let (_id) = current_id.read();
    let (ido_contract_class: felt) = get_ido_contract_class_hash();
    with_attr error_message("IDO contract class hash is not set") {
        assert_not_zero(ido_contract_class);
    }
    let (new_ido_contract_address: felt) = deploy(
        class_hash=ido_contract_class,
        contract_address_salt=_id,
        constructor_calldata_size=1,
        constructor_calldata=cast(new (ido_admin), felt*),
        deploy_from_zero=0,
    );
    ido_contract_addresses.write(_id, new_ido_contract_address);
    scorer_addresses.write(_id, scorer);
    current_id.write(_id + 1);
    IDO_Created.emit(_id, new_ido_contract_address);
    return (new_ido_contract_address,);
}

@external
func create_ino{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ido_admin: felt, scorer: felt
) -> (new_ino_contract_address: felt) {
    alloc_locals;
    AstralyAccessControl.assert_only_owner();
    let (_id) = current_id.read();
    let (ino_contract_class: felt) = get_ino_contract_class_hash();
    with_attr error_message("INO contract class hash is not set") {
        assert_not_zero(ino_contract_class);
    }
    let (new_ino_contract_address: felt) = deploy(
        class_hash=ino_contract_class,
        contract_address_salt=_id,
        constructor_calldata_size=1,
        constructor_calldata=cast(new (ido_admin), felt*),
        deploy_from_zero=0,
    );
    ino_contract_addresses.write(_id, new_ino_contract_address);
    scorer_addresses.write(_id, scorer);
    current_id.write(_id + 1);
    INO_Created.emit(_id, new_ino_contract_address);
    return (new_ino_contract_address,);
}

@external
func set_random_number_generator_address{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(rnd_nbr_gen_adr: felt) {
    AstralyAccessControl.assert_only_owner();
    with_attr error_message("Invalid address") {
        assert_not_zero(rnd_nbr_gen_adr);
    }
    random_number_generator_address.write(rnd_nbr_gen_adr);
    return ();
}

@external
func set_payment_token_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _pmt_tkn_addr: felt
) {
    AstralyAccessControl.assert_only_owner();
    with_attr error_message("Invalid address") {
        assert_not_zero(_pmt_tkn_addr);
    }
    payment_token_address.write(_pmt_tkn_addr);
    return ();
}

@external
func set_merkle_root{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _merkle_root: felt, _id: felt
) {
    AstralyAccessControl.assert_only_owner();
    // with_attr error_message("Invalid id"):
    //     assert_not_zero(_id)
    // end
    with_attr error_message("Invalid merkle root") {
        assert_not_zero(_merkle_root);
    }
    merkle_root.write(_id, _merkle_root);
    return ();
}

@external
func set_ido_contract_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_class_hash: felt
) {
    AstralyAccessControl.assert_only_owner();
    with_attr error_message("Invalid contract class hash") {
        assert_not_zero(new_class_hash);
    }
    ido_contract_class_hash.write(new_class_hash);
    return ();
}

@external
func set_ino_contract_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_class_hash: felt
) {
    AstralyAccessControl.assert_only_owner();
    with_attr error_message("Invalid contract class hash") {
        assert_not_zero(new_class_hash);
    }
    ino_contract_class_hash.write(new_class_hash);
    return ();
}
