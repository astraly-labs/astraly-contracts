%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_equal

from openzeppelin.access.accesscontrol.library import AccessControl

const OWNER_ROLE = 'OWNER';

namespace AstralyAccessControl {
    func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(owner: felt) {
        AccessControl.initializer();
        AccessControl._set_role_admin(OWNER_ROLE, OWNER_ROLE);
        AccessControl._grant_role(OWNER_ROLE, owner);
        return ();
    }

    func assert_only_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
        AccessControl.assert_only_role(OWNER_ROLE);
        return ();
    }

    func assert_only_role{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        role: felt
    ) {
        AccessControl.assert_only_role(role);
        return ();
    }

    func transfer_ownership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        new_owner: felt
    ) {
        assert_only_owner();
        let (caller) = get_caller_address();
        AccessControl.renounce_role(OWNER_ROLE, caller);
        AccessControl._grant_role(OWNER_ROLE, new_owner);
        return ();
    }

    func grant_role{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        role: felt, user: felt
    ) {
        alloc_locals;
        assert_only_owner();
        with_attr error_message("AccessControl: Can't grant owner role") {
            assert_not_equal(role, OWNER_ROLE);
        }
        let (role_admin: felt) = AccessControl.get_role_admin(role);
        let (owner) = get_caller_address();
        if (role_admin != owner) {
            AccessControl._set_role_admin(role, OWNER_ROLE);
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar pedersen_ptr: HashBuiltin* = pedersen_ptr;
            tempvar syscall_ptr: felt* = syscall_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        AccessControl.grant_role(role, user);
        return ();
    }

    func is_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        address: felt
    ) -> (have_owner_role: felt) {
        let (has_owner_role: felt) = AccessControl.has_role(OWNER_ROLE, address);
        return (has_owner_role,);
    }

    func has_role{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        role: felt, user: felt
    ) -> (has_role: felt) {
        let (res: felt) = AccessControl.has_role(role, user);
        return (res,);
    }
}
