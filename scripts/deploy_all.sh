#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner
# TODO: Use this only on devnet, otherwise comment next lines
# export STARKNET_GATEWAY_URL=http://127.0.0.1:5000
# export STARKNET_FEEDER_GATEWAY_URL=http://127.0.0.1:5000

SALT=0x4
MAX_FEE=54452800237082000
SLEEP=400

OWNER_ADDRESS=0x02356b628d108863Baf8644C945d97bAD70190aF5957031F4852D00D0f690a77
NUMBER_OF_ADMINS=2
ADMINS_ADDRESSES="${OWNER_ADDRESS} ${OWNER_ADDRESS}"

LOTTERY_URI_LEN=2
LOTTERY_URI_0=186294699441980128189380696103414374861828827125449954958229537633255900247
LOTTERY_URI_1=43198068668795004939573357158436613902855023868408433
XOROSHIRO_RNG_SEED=984375843

ZKP_NAME=0x41737472616c79 # hex(str_to_felt("Astraly"))
ZKP_SYMBOL=0x41535452 # hex(str_to_felt("ASTR"))
DECIMALS=18
INITIAL_SUPPLY=10000000000000000000000000
RECIPIENT=${OWNER_ADDRESS}
MAX_SUPPLY=100000000000000000000000000  # TODO: check value before deploy

XZKP_NAME=0x7841737472616c79 # hex(str_to_felt("xAstraly"))
XZKP_SYMBOL=0x7841535452 # hex(str_to_felt("xZKP"))
REWARD_PER_BLOCK=10000000000000000000 # 10 ether

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/AstralyStaking.cairo --output ./artifacts/AstralyStaking.json --abi ./artifacts/AstralyStaking_abi.json
starknet-compile ./contracts/AstralyVaultHarvestTask.cairo --output ./artifacts/AstralyVaultHarvestTask.json --abi ./artifacts/AstralyVaultHarvestTask_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
starknet-compile ./contracts/AstralyToken.cairo --output ./artifacts/AstralyToken.json --abi ./artifacts/AstralyToken_abi.json
starknet-compile ./contracts/AstralyAdmin.cairo --output ./artifacts/AstralyAdmin.json --abi ./artifacts/AstralyAdmin_abi.json
starknet-compile ./contracts/AstralyLotteryToken.cairo --output ./artifacts/AstralyLotteryToken.json --abi ./artifacts/AstralyLotteryToken_abi.json
starknet-compile ./contracts/AstralyIDOFactory.cairo --output ./artifacts/AstralyIDOFactory.json --abi ./artifacts/AstralyIDOFactory_abi.json
starknet-compile ./contracts/AstralyINOContract.cairo --output ./artifacts/AstralyINOContract.json --abi ./artifacts/AstralyINOContract_abi.json
starknet-compile ./contracts/utils/xoroshiro128_starstar.cairo --output ./artifacts/xoroshiro128_starstar.json --abi ./artifacts/xoroshiro128_starstar_abi.json
printf "Contract compile successfully\n"

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare AstralyStaking class"
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/AstralyStaking.json)
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")

echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json 

echo "Declare AstralyVaultHarvestTask"
starknet declare --contract ../artifacts/AstralyVaultHarvestTask.json

echo "Declare AstralyAdmin"
# starknet declare --contract ../artifacts/AstralyAdmin.json

echo "Declare AstralyToken"
# starknet declare --contract ../artifacts/AstralyToken.json

echo "Declare AstralyLotteryToken"
# starknet declare --contract ../artifacts/AstralyLotteryToken.json

echo "Declare AstralyIDOFactory"
# starknet declare --contract ../artifacts/AstralyIDOFactory.json

echo "Declare xoroshiro128_starstar"
# starknet declare --contract ../artifacts/xoroshiro128_starstar.json
printf "Declare successfully\n"

echo "Declare AstralyIDO class"
ZK_PAD_IDO_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/AstralyIDOContract.json)
echo "${ZK_PAD_IDO_DECLARATION_OUTPUT}"
ZK_PAD_IDO_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_IDO_DECLARATION_OUTPUT}")
echo "Declare AstralyINO class"
ZK_PAD_INO_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/AstralyINOContract.json)
echo "${ZK_PAD_INO_DECLARATION_OUTPUT}"
ZK_PAD_INO_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_INO_DECLARATION_OUTPUT}")

################################################################################## DEPLOY ##########################################################################################
# echo "Deploy AstralyStaking"
# starknet deploy --contract ../artifacts/AstralyStaking.json --salt ${SALT} 

# echo "Deploy OZProxy"
# ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/OZProxy.json --salt ${SALT} --inputs "${ZK_PAD_STAKING_CLASS_HASH}")
# echo "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}"
# ZK_PAD_STAKING_PROXY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}")

# echo "Deploy AstralyVaultHarvestTask"
# starknet deploy --contract ../artifacts/AstralyVaultHarvestTask.json --inputs "${ZK_PAD_STAKING_PROXY_ADDRESS}" --salt ${SALT}

# echo "Deploy AstralyAdmin"
# starknet deploy --contract ../artifacts/AstralyAdmin.json --inputs "${NUMBER_OF_ADMINS}" ${ADMINS_ADDRESSES} --salt ${SALT}

# echo "Deploy AstralyIDOFactory"
# ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/AstralyIDOFactory.json --inputs "${ZK_PAD_IDO_CLASS_HASH}" ${OWNER_ADDRESS} --salt ${SALT})
# echo "${ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT}"
# ZK_PAD_IDO_FACTORY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT}")

# echo "Deploy AstralyLotteryToken"
# ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/AstralyLotteryToken.json --inputs ${LOTTERY_URI_LEN} "${LOTTERY_URI_0}" "${LOTTERY_URI_1}" ${OWNER_ADDRESS} "${ZK_PAD_IDO_FACTORY_ADDRESS}" --salt ${SALT})
# echo "${ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT}"
# ZK_PAD_LOTTERY_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT}")

# echo "Deploy xoroshiro128_starstar"
# starknet deploy --contract ../artifacts/xoroshiro128_starstar.json --inputs "${XOROSHIRO_RNG_SEED}" --salt ${SALT}

# echo "Deploy AstralyToken"
# ZK_PAD_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/AstralyToken.json --salt ${SALT} \
#     --inputs ${ZKP_NAME} ${ZKP_SYMBOL} ${DECIMALS} ${INITIAL_SUPPLY} 0 ${RECIPIENT} ${OWNER_ADDRESS} ${MAX_SUPPLY} 0)
# echo "${ZK_PAD_DEPLOYMENT_RECEIPT}"
# ZKP_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_DEPLOYMENT_RECEIPT}")
# printf "Deploy successfully\n"

echo "CONTRACTS DEPLOYMENT DONE 🚀"

################################################################################## INITIALIZE ##########################################################################################
# CURRENT_BLOCK_NUMBER=$(starknet get_block | jq '.block_number')
# START_BLOCK=243000
# END_BLOCK=450000

# echo "Initialize the vault"
# starknet invoke --address "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
#     --abi ../artifacts/AstralyStaking_abi.json \
#     --function initializer \
#     --inputs ${XZKP_NAME} ${XZKP_SYMBOL} "${ZKP_TOKEN_ADDRESS}" ${OWNER_ADDRESS} ${REWARD_PER_BLOCK} 0 "${START_BLOCK}" "${END_BLOCK}" \
#     --max_fee ${MAX_FEE} \
#     --account ${OWNER_ACCOUNT_NAME} \
   

sleep ${SLEEP}
echo "Initialize successfully"


echo "Set xZKP contract address for lottery token"
starknet invoke --address "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --abi ../artifacts/AstralyLotteryToken_abi.json \
    --function set_xzkp_contract_address \
    --inputs "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   
sleep ${SLEEP}
echo "xZKP address set successfully"

echo "Set xZKP contract address for token"
starknet invoke --address "${ZKP_TOKEN_ADDRESS}" \
    --abi ../artifacts/AstralyToken_abi.json \
    --function set_vault_address \
    --inputs "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   
sleep ${SLEEP}
echo "xZKP address set successfully"

echo "Set IDO factory address"
starknet invoke --address "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --abi ../artifacts/AstralyLotteryToken_abi.json \
    --function set_ido_factory_address \
    --inputs "${ZK_PAD_IDO_FACTORY_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   
sleep ${SLEEP}
echo "IDO factory address set"

echo "Set lottery ticket contract address"
starknet invoke --address "${ZK_PAD_IDO_FACTORY_ADDRESS}" \
    --abi ../artifacts/AstralyIDOFactory_abi.json \
    --function set_lottery_ticket_contract_address \
    --inputs "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   

sleep ${SLEEP}
echo "Lottery ticket contract address set successfully"


echo "CONTRACTS SUCCESSFULLY INITIALIZED 🚀"
