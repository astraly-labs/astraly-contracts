#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

# TODO: Use this only on devnet, otherwise comment next line
export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
SALT=0x1
MAX_FEE=1

OWNER_ADDRESS=0xc45388638835815ffbee415184905349efdc167540105c2ab022361d5bfca5
ZKP_TOKEN_ADDRESS=0x01
IDO_TOKEN_PRICE="10000000000000000 0"
IDO_TOKENS_TO_SELL="100000000000000000000000 0"
# vesting portion percentages must add up to 1000
IDO_PORTION_VESTING_PRECISION="1000 0"
# users can't burn more than 10000 lottery tickets
IDO_LOTTERY_TOKENS_BURN_CAP="10000 0"
# Timestamp values
day=$(date +%s) # TODAY TIMESTAMP
timeDeltaDays=$((30 * 24 * 60 * 60))
timeDeltaWeeks=$((7 * 24 * 60 * 60))
IDO_SALE_END=$((day + timeDeltaDays))
REGISTRATION_END=$((day + (2 * 24 * 60 * 60)))
REGISTRATION_START=$((day + (1 * 24 * 60 * 60)))
IDO_TOKEN_UNLOCK=$(($IDO_SALE_END + $timeDeltaWeeks))
# VESTING_PERCENTAGES & VESTING_TIMES_UNLOCKED arrays must match in length
VESTING_PERCENTAGES_LEN=4
VESTING_PERCENTAGES="100 0 200 0 300 0 400 0"
VESTING_TIMES_UNLOCKED_LEN=4
VESTING_TIMES_UNLOCKED="86401 691201 1296001 1900801"

ZK_PAD_FACTORY_ADDRESS=0x069bcaad4741a83821040ad395805c34d1d5e69f5eede024bbd6b6f5aac7bdbc

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/ZkPadIDOContract.cairo --output ./artifacts/ZkPadIDOContract.json --abi ./artifacts/ZkPadIDOContract_abi.json
starknet-compile ./contracts/ZkPadTask.cairo --output ./artifacts/ZkPadTask.json --abi ./artifacts/ZkPadTask_abi.json

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare ZkPadIDOContract"
starknet declare --contract ../artifacts/ZkPadIDOContract.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadTask"
starknet declare --contract ../artifacts/ZkPadTask.json $STARKNET_DEVNET_ARGUMENTS


################################################################################## DEPLOY ##########################################################################################
echo "Deploy ZkPadTask"
ZK_PAD_TASK_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadTask.json --inputs ${ZK_PAD_FACTORY_ADDRESS} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_TASK_DEPLOYMENT_RECEIPT}"
ZKP_TASK_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_TASK_DEPLOYMENT_RECEIPT}")


echo "Deploy ZkPadIDOContract"
ZK_PAD_IDO_CONTRACT_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadIDOContract.json --inputs ${OWNER_ADDRESS} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_IDO_CONTRACT_DEPLOYMENT_RECEIPT}"
ZKP_IDO_CONTRACT_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_IDO_CONTRACT_DEPLOYMENT_RECEIPT}")


echo "Set Task Address"
starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
    --abi ../artifacts/ZkPadIDOFactory_abi.json \
    --function set_task_address \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs "${ZKP_TASK_ADDRESS}" \
    $STARKNET_DEVNET_ARGUMENTS


echo "Create IDO"
starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
    --abi ../artifacts/ZkPadIDOFactory_abi.json \
    --function create_ido \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS


starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_sale_params \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${ZKP_TOKEN_ADDRESS} ${OWNER_ADDRESS} ${IDO_TOKEN_PRICE} ${IDO_TOKENS_TO_SELL} ${IDO_SALE_END} ${IDO_TOKEN_UNLOCK} ${IDO_PORTION_VESTING_PRECISION} ${IDO_LOTTERY_TOKENS_BURN_CAP}\
    $STARKNET_DEVNET_ARGUMENTS

starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_vesting_params \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${VESTING_TIMES_UNLOCKED_LEN} ${VESTING_TIMES_UNLOCKED} ${VESTING_PERCENTAGES_LEN} ${VESTING_PERCENTAGES} 0 \
    $STARKNET_DEVNET_ARGUMENTS

starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_registration_time \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${REGISTRATION_START} ${REGISTRATION_END} \
    $STARKNET_DEVNET_ARGUMENTS


echo "IDO SUCCESSFULLY CREATED 🚀"
exit