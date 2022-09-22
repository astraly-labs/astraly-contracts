%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

from openzeppelin.upgrades.library import Proxy

@view
func getImplementationHash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    address: felt
) {
    let (class_hash) = Proxy.get_implementation_hash();
    return (class_hash,);
}
