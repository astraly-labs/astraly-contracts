%lang starknet

from starknet.types import Keccak256Hash

@contract_interface
namespace IL1HeadersStore:
    func get_parent_hash(block_number : felt) -> (res : Keccak256Hash):
    end

    func get_state_root(block_number : felt) -> (res : Keccak256Hash):
    end

    func get_transactions_root(block_number : felt) -> (res : Keccak256Hash):
    end

    func get_receipts_root(block_number : felt) -> (res : Keccak256Hash):
    end

    func get_uncles_hash(block_number : felt) -> (res : Keccak256Hash):
    end
end
