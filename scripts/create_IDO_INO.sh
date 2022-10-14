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

# clean the protostar project
clean() {
    log_info "Cleaning..."
    if [ $? -ne 0 ]; then exit_error "Problem during clean"; fi
}

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


deploy_ido_factory() {
    owner_address=$1
    log_info "Deploying IDO Factory"
    RESULT=`send_transaction "starknet $NETWORK_OPT deploy --no_wallet --contract ./artifacts/AstralyIDOFactory.json --inputs $owner_address"`
    echo $RESULT
}

create_ido() {
    factory_address=$1
    ido_admin=$2
    scorer=$3
    admin_cut=$4
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $factory_address --abi ./artifacts/abis/AstralyIDOFactory.json --function create_ido --inputs $ido_admin $scorer $admin_cut"` || exit_error
}

create_ino(){
    factory_address=$1
    ino_admin=$2
    scorer=$3
    admin_cut=$4
    RESULT=`send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $factory_address --abi ./artifacts/abis/AstralyIDOFactory.json --function create_ino --inputs $ido_admin $scorer $admin_cut"` || exit_error  
}

# Deploy all contracts and log the deployed addresses in the cache file
deploy_all_contracts() {
    [ -f $CACHE_FILE ] && {
        . $CACHE_FILE
        log_info "Found those deployed accounts:"
        cat $CACHE_FILE
        ask "\nDo you want to deploy missing contracts and initialize them" || return 
    }

    print Admin account alias: $ADMIN_ACCOUNT
    print Admin account address: $ADMIN_ADDRESS
    print Network option: $NETWORK_OPT

    ask "Are you OK to deploy with those parameters" || return 
    ask "Is the factory deployed ?"
    if [ $? -ne 0 ]; then
        log_info "Deploying factory"
        FACTORY_ADDRESS=`deploy_ido_factory $ADMIN_ADDRESS` || exit_error
        (
        echo "FACTORY_ADDRESS=$FACTORY_ADDRESS"
        ) | tee>&2 $CACHE_FILE
    fi
    # factory_address=$(cat $CACHE_FILE)
    factory_address=$(awk '/FACTORY_ADDRESS/{print substr($0,length($0)-65)}' $CACHE_FILE)
    ask "create IDO ?"
    case $? in 
        0) log_info "Creating IDO"
        contract="AstralyIDOContract"
        factory="AstralyIDOFactory"
        ask "Do you want to upgrade contract hash"
        if [ $? -eq 0 ]; then 
            log_info "Updating the contract hash"
            ido_class_hash=`send_declare_contract_transaction "starknet declare $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --contract ./artifacts/${contract}.json"` || exit_error
            send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $factory_address --abi ./artifacts/abis/${factory}.json --function set_ido_contract_class_hash --inputs $ido_class_hash" || exit_error  
        fi
        `create_ido $factory_address $ADMIN_ADDRESS $SCORER $ADMIN_CUT `
        ;;
        1) log_info "Creating INO"
        contract="AstralyINOContract"
        factory="AstralyIDOFactory"
        ask "Do you want to upgrade contract hash"
        if [ $? -eq 0 ]; then 
            log_info "Updating the contract hash"
            ino_class_hash=`send_declare_contract_transaction "starknet declare $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --contract ./artifacts/${contract}.json"` || exit_error
            send_transaction "starknet invoke $ACCOUNT_OPT $NETWORK_OPT $MAX_FEE_OPT --address $factory_address --abi ./artifacts/abis/${factory}.json --function set_ino_contract_class_hash --inputs $ino_class_hash" || exit_error  
        fi
        `create_ino $factory_address $ADMIN_ADDRESS $SCORER $ADMIN_CUT `
        ;;
        esac
}

### ARGUMENT PARSING
while getopts a:s:c:m:p:yh option
do
    case "${option}"
    in
        a) ADMIN_ACCOUNT=${OPTARG};;
        p) NETWORK=${OPTARG};;
        m) MAX_FEE=${OPTARG};;
        y) AUTO_YES="true";;
        h) usage; exit_success;;
        s) SCORER=${OPTARG};;
        c) ADMIN_CUT=${OPTARG};;
        \?) usage; exit_error;;
    esac
done

export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount

[ -z "$ADMIN_ACCOUNT" ] && exit_error "Admin account is mandatory (use -a option) and must be set to the alias of the admin account"
[ -z $SCORER ] && exit_error "Scorer is mandatory (use -s option)"
[ -z $ADMIN_CUT ] && exit_error "Admin cut is mandatory (use -s option)"

CACHE_FILE="${CACHE_FILE_BASE}.txt"

ADMIN_ADDRESS=`get_account_address $ADMIN_ACCOUNT`
[ -z $ADMIN_ADDRESS ] && exit_error "Unable to determine account address"

[ -z "$NETWORK" ] && exit_error "Unable to determine network option"

ACCOUNT_OPT="--account $ADMIN_ACCOUNT"
NETWORK_OPT="--network $NETWORK"
MAX_FEE_OPT="--max_fee $MAX_FEE"

### PRE_CONDITIONS
check_starknet

### BUSINESS LOGIC

clean # Need to remove ABI and compiled contracts that may not exist anymore (eg. migrations)
build # Need to generate ABI and compiled contracts
deploy_all_contracts

exit_success