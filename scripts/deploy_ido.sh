#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

# TODO: Use this only on devnet, otherwise comment next line
# export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
SALT=0x1
MAX_FEE=54452800237082000

OWNER_ADDRESS=0x02356b628d108863Baf8644C945d97bAD70190aF5957031F4852D00D0f690a77
ZKP_TOKEN_ADDRESS=0x05a6b68181bb48501a7a447a3f99936827e41d77114728960f22892f02e24928
IDO_TOKEN_PRICE="100000000000000000 0" # 0,1 ETH
IDO_TOKENS_TO_SELL="10000000000000000000000 0" # 10_000 TOKENS
# vesting portion percentages must add up to 1000
IDO_PORTION_VESTING_PRECISION="1000 0"
# users can't burn more than 100 lottery tickets
IDO_LOTTERY_TOKENS_BURN_CAP="100 0"
# Timestamp values
day=1655481600 # LAUNCH TIMESTAMP
timeDelta_Days=$((8 * 24 * 60 * 60)) # 8 days
IDO_SALE_END=$((day + timeDelta_Days))
REGISTRATION_START=$((day + (4 * 24 * 60 * 60))) # 1 day after
REGISTRATION_END=$((day + (6 * 24 * 60 * 60))) # 2 days after
IDO_TOKEN_UNLOCK=$(($IDO_SALE_END))
# VESTING_PERCENTAGES & VESTING_TIMES_UNLOCKED arrays must match in length
VESTING_PERCENTAGES_LEN=4
VESTING_PERCENTAGES="100 0 200 0 300 0 400 0"
VESTING_TIMES_UNLOCKED_LEN=4
VESTING_TIMES_UNLOCKED="1656345600 1656518400 1656691200 1656864000"

ZK_PAD_FACTORY_ADDRESS=0x04db841c9371a7b84de3bcf69dcb5946eb81793b405228bf5862995f1d08023b
ZKP_IDO_CONTRACT_ADDRESS=0x54c365244b4b7129b2fcf0b4909aca7ce437ae2ee5620f7c5bc0bbbb70238a1
################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/ZkPadTask.cairo --output ./artifacts/ZkPadTask.json --abi ./artifacts/ZkPadTask_abi.json
starknet-compile ./contracts/ZkPadIDOContract.cairo --output ./artifacts/ZkPadIDOContract.json --abi ./artifacts/ZkPadIDOContract_abi.json

################################################################################## DECLARE ##########################################################################################
cd ./contracts
# echo "Declare ZkPadTask"
# starknet declare --contract ../artifacts/ZkPadTask.json $STARKNET_DEVNET_ARGUMENTS
# echo "Declare ZkPadIDO class"
# ZK_PAD_IDO_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadIDOContract.json $STARKNET_DEVNET_ARGUMENTS)
# echo "${ZK_PAD_IDO_DECLARATION_OUTPUT}"
# ZK_PAD_IDO_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_IDO_DECLARATION_OUTPUT}")

################################################################################## DEPLOY ##########################################################################################
# echo "Deploy ZkPadTask"
# ZK_PAD_TASK_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadTask.json --inputs ${ZK_PAD_FACTORY_ADDRESS} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
# echo "${ZK_PAD_TASK_DEPLOYMENT_RECEIPT}"
# ZKP_TASK_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_TASK_DEPLOYMENT_RECEIPT}")

# echo "Set Task Address"
# starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
#     --abi ../artifacts/ZkPadIDOFactory_abi.json \
#     --function set_task_address \
#     --max_fee ${MAX_FEE} \
#     --account ${OWNER_ACCOUNT_NAME} \
#     --inputs "${ZKP_TASK_ADDRESS}" \
#     $STARKNET_DEVNET_ARGUMENTS

# sleep 400

# echo "Set IDO Class Hash"
# starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
#     --abi ../artifacts/ZkPadIDOFactory_abi.json \
#     --function set_ido_contract_class_hash \
#     --max_fee ${MAX_FEE} \
#     --account ${OWNER_ACCOUNT_NAME} \
#     --inputs "${ZK_PAD_IDO_CLASS_HASH}" \
#     $STARKNET_DEVNET_ARGUMENTS

# sleep 400


# echo "Create IDO"
# starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
#     --abi ../artifacts/ZkPadIDOFactory_abi.json \
#     --function create_ido \
#     --max_fee ${MAX_FEE} \
#     --account ${OWNER_ACCOUNT_NAME} \
#     $STARKNET_DEVNET_ARGUMENTS

# sleep 400


starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_sale_params \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${ZKP_TOKEN_ADDRESS} ${OWNER_ADDRESS} ${IDO_TOKEN_PRICE} ${IDO_TOKENS_TO_SELL} ${IDO_SALE_END} ${IDO_TOKEN_UNLOCK} ${IDO_PORTION_VESTING_PRECISION} ${IDO_LOTTERY_TOKENS_BURN_CAP}\
    $STARKNET_DEVNET_ARGUMENTS

sleep 400

starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_vesting_params \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${VESTING_TIMES_UNLOCKED_LEN} ${VESTING_TIMES_UNLOCKED} ${VESTING_PERCENTAGES_LEN} ${VESTING_PERCENTAGES} 0 \
    $STARKNET_DEVNET_ARGUMENTS

sleep 400

starknet invoke --address ${ZKP_IDO_CONTRACT_ADDRESS} \
    --abi ../artifacts/ZkPadIDOContract_abi.json \
    --function set_registration_time \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    --inputs ${REGISTRATION_START} ${REGISTRATION_END} \
    $STARKNET_DEVNET_ARGUMENTS


echo "IDO SUCCESSFULLY CREATED 🚀"
exit