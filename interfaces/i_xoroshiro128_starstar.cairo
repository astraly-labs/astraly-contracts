%lang starknet

@contract_interface
namespace IXoroshiro128Starstar {
    func update_seed(seed: felt) {
    }

    func next() -> (rnd: felt) {
    }

    func get_winning_tickets(_burnt_tickets: felt, _random_number: felt) -> (res: felt) {
    }
}
