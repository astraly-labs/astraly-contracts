#!/bin/bash

### CONSTANTS
SCRIPT_DIR=`readlink -f $0 | xargs dirname`
ROOT=`readlink -f $SCRIPT_DIR/..`
CACHE_FILE_BASE=$ROOT/scripts/configuration/deployed_contracts
STARKNET_ACCOUNTS_FILE=$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json
PROTOSTAR_TOML_FILE=$ROOT/protostar.toml
STARKNET_VERSION="0.10.0"

### FUNCTIONS
. $SCRIPT_DIR/logging.sh # Logging utilities
. $SCRIPT_DIR/tools.sh   # script utilities


# build the protostar project
build() {
    log_info "Building project to generate latest version of the ABI"
    execute nile compile
    if [ $? -ne 0 ]; then exit_error "Problem during build"; fi
}

# get the account address from the account alias in protostar accounts file
# $1 - account alias (optional). __default__ if not provided
get_account_address() {
    [ $# -eq 0 ] && account=__default__ || account=$1
    grep $account $STARKNET_ACCOUNTS_FILE -A3 -m1 | sed -n 's@^.*"address": "\(.*\)".*$@\1@p'
}

# get the network option from the profile in protostar config file
# $1 - profile
get_network_opt() {
    profile=$1
    grep profile.$profile $PROTOSTAR_TOML_FILE -A5 -m1 | sed -n 's@^.*network_opt = "\(.*\)".*$@\1@p'
}

# check starknet binary presence
check_starknet() {
    which starknet &> /dev/null
    [ $? -ne 0 ] && exit_error "Unable to locate starknet binary. Did you activate your virtual env ?"
    version=$(starknet -v)
    if [ "$version" != "starknet $STARKNET_VERSION" ]; then
        exit_error "Invalid starknet version: $version. Version $STARKNET_VERSION is required"
    fi
}

# wait for a transaction to be received
# $1 - transaction hash to check
wait_for_acceptance() {
    tx_hash=$1
    print -n $(magenta "Waiting for transaction to be accepted")
    while true 
    do
        tx_status=`starknet tx_status --hash $tx_hash $NETWORK_OPT | sed -n 's@^.*"tx_status": "\(.*\)".*$@\1@p'`
        case "$tx_status"
            in
                NOT_RECEIVED|RECEIVED|PENDING) print -n  $(magenta .);;
                REJECTED) return 1;;
                ACCEPTED_ON_L1|ACCEPTED_ON_L2) return 0; break;;
                *) exit_error "\nUnknown transaction status '$tx_status'";;
            esac
            sleep 2
    done
}

# send a transaction
# $* - command line to execute
# return The contract address
send_transaction() {
    transaction=$*

    while true
    do
        execute $transaction || exit_error "Error when sending transaction"
        
        contract_address=`sed -n 's@Contract address: \(.*\)@\1@p' logs.json`
        tx_hash=`sed -n 's@Transaction hash: \(.*\)@\1@p' logs.json`

        wait_for_acceptance $tx_hash

        case $? in
            0) log_success "\nTransaction accepted!"; break;;
            1) log_warning "\nTransaction rejected!"; ask "Do you want to retry";;
        esac
    done || exit_error

    echo $contract_address
}

# send a transaction that declares a contract class
# $* - command line to execute
# return The contract address
send_declare_contract_transaction() {
    transaction=$*

    while true
    do
        execute $transaction || exit_error "Error when sending transaction"
        
        contract_class_hash=`sed -n 's@Contract class hash: \(.*\)@\1@p' logs.json`
        tx_hash=`sed -n 's@Transaction hash: \(.*\)@\1@p' logs.json`

        wait_for_acceptance $tx_hash

        case $? in
            0) log_success "\nTransaction accepted!"; break;;
            1) log_warning "\nTransaction rejected!"; ask "Do you want to retry";;
        esac
    done || exit_error

    echo $contract_class_hash
}
set_vesting_params(){
    VESTING_PERCENTAGES_LEN=4
    VESTING_PERCENTAGES="100 0 200 0 300 0 400 0"
    VESTING_TIMES_UNLOCKED_LEN=4
    VESTING_TIMES_UNLOCKED="1656345600 1656518400 1656691200 1656864000"
    contract=$1
    ido_ino_contract_address=$2
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $ido_ino_contract_address --abi ./artifacts/abis/${contract}.json --function set_vesting_params --inputs ${VESTING_TIMES_UNLOCKED_LEN} ${VESTING_TIMES_UNLOCKED} ${VESTING_PERCENTAGES_LEN} ${VESTING_PERCENTAGES}"` || exit_error  
}

set_registration_time(){
    day=1655481600 # LAUNCH TIMESTAMP
    REGISTRATION_START=$((day + (4 * 24 * 60 * 60))) # 4 day after
    REGISTRATION_END=$((day + (6 * 24 * 60 * 60))) # 6 days after
    contract=$1
    ido_ino_contract_address=$2
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $ido_ino_contract_address --abi ./artifacts/abis/${contract}.json --function set_registration_time --inputs ${REGISTRATION_START} ${REGISTRATION_END}"` || exit_error  
}

set_purchase_round_params(){
    _purchase_time_starts=1
    _purchase_time_ends=1
    max_participation="1 0"
    contract=$1
    ido_ino_contract_address=$2
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $ido_ino_contract_address --abi ./artifacts/abis/${contract}.json --function set_purchase_round_params --inputs $_purchase_time_starts $_purchase_time_ends ${max_participation}"` || exit_error  

}

set_sale_params(){
    _token_address=0xe858cbbdebb793977a9dbbbed0afc78e2a4c841c0af1165308b58d82255343
    _sale_owner_address=0xe858cbbdebb793977a9dbbbed0afc78e2a4c841c0af1165308b58d82255
    _token_price="1 0"
    _amount_of_tokens_to_sell="1 0"
    _sale_end_time=1
    _tokens_unlock_time=1
    _portion_vesting_precision="30 0"
    _base_allocation="1 0"
    contract=$1
    ido_ino_contract_address=$2
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $ido_ino_contract_address --abi ./artifacts/abis/${contract}.json --function set_sale_params --inputs $_token_address $_sale_owner_address ${_token_price} ${_amount_of_tokens_to_sell} $_sale_end_time $_tokens_unlock_time ${_portion_vesting_precision} ${_base_allocation}"` || exit_error  

}
setup_ido_ino () {
    ask "Do you want to setup an IDO or an INO ? [0/1]"
    case $? in 
        0) log_info "Setting up an IDO..."
        contract="AstralyIDOContract"
        ;;
        1) log_info "Setting up an INO"
        contract="AstralyINOContract"
        ;;
        esac
    `set_sale_params $contract $IDO_INO_CONTRACT_ADDRESS `
    `set_vesting_params $contract $IDO_INO_CONTRACT_ADDRESS `
    `set_registration_time $contract $IDO_INO_CONTRACT_ADDRESS `
    `set_purchase_round_params $contract $IDO_INO_CONTRACT_ADDRESS `
}


### ARGUMENT PARSING
while getopts a:m:p:yh option
do
    case "${option}"
    in
        a) ADMIN_ACCOUNT=${OPTARG};;
        p) NETWORK=${OPTARG};;
        m) MAX_FEE=${OPTARG};;
        y) AUTO_YES="true";;
        h) usage; exit_success;;
        \?) usage; exit_error;;
    esac
done

export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount

[ -z "$ADMIN_ACCOUNT" ] && exit_error "Admin account is mandatory (use -a option) and must be set to the alias of the admin account"

CACHE_FILE="${CACHE_FILE_BASE}.txt"

ADMIN_ADDRESS=`get_account_address $ADMIN_ACCOUNT`
[ -z $ADMIN_ADDRESS ] && exit_error "Unable to determine account address"

[ -z "$NETWORK" ] && exit_error "Unable to determine network option"

ACCOUNT_OPT="--account $ADMIN_ACCOUNT"
NETWORK_OPT="--network $NETWORK"
MAX_FEE_OPT="--max_fee $MAX_FEE"
IDO_INO_CONTRACT_ADDRESS=0xe858cbbdebb793977a9dbbbed0afc78e2a4c841c0af1165308b58d822553b9
### PRE_CONDITIONS
check_starknet

### BUSINESS LOGIC
build # Need to generate ABI and compiled contracts
setup_ido_ino

exit_success