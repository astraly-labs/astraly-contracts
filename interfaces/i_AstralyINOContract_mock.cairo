%lang starknet

@contract_interface
namespace IAstralyinocontractMock {
    func register_users(users_len: felt, users: felt*, score_arr_len: felt, score_arr: felt*) {
    }

    func get_winners() -> (arr_len: felt, arr: felt*) {
    }
}
