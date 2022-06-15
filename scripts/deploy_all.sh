#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

# TODO: Use this only on devnet, otherwise comment next line
# export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
SALT=0x1
MAX_FEE=54452800237082000
SLEEP=400

OWNER_ADDRESS=0x02356b628d108863Baf8644C945d97bAD70190aF5957031F4852D00D0f690a77
NUMBER_OF_ADMINS=2
ADMINS_ADDRESSES="${OWNER_ADDRESS} ${OWNER_ADDRESS}"

LOTTERY_URI_LEN=2
LOTTERY_URI_0=186294699441980128189380696103414374861828827125449954958229537633255900247
LOTTERY_URI_1=43198068668795004939573357158436613902855023868408433
XOROSHIRO_RNG_SEED=984375843

ZKP_NAME=0x5a6b506164 # hex(str_to_felt("ZkPad"))
ZKP_SYMBOL=0x5a4b50 # hex(str_to_felt("ZKP"))
DECIMALS=18
INITIAL_SUPPLY=10000000000000000000000000
RECIPIENT=${OWNER_ADDRESS}
MAX_SUPPLY=100000000000000000000000000  # TODO: check value before deploy

XZKP_NAME=0x785a6b506164 # hex(str_to_felt("xZkPad"))
XZKP_SYMBOL=0x785a4b50 # hex(str_to_felt("xZKP"))
REWARD_PER_BLOCK=10000000000000000000 # 10 ether

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/ZkPadStaking.cairo --output ./artifacts/ZkPadStaking.json --abi ./artifacts/ZkPadStaking_abi.json
starknet-compile ./contracts/ZkPadVaultHarvestTask.cairo --output ./artifacts/ZkPadVaultHarvestTask.json --abi ./artifacts/ZkPadVaultHarvestTask_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
starknet-compile ./contracts/ZkPadToken.cairo --output ./artifacts/ZkPadToken.json --abi ./artifacts/ZkPadToken_abi.json
starknet-compile ./contracts/ZkPadAdmin.cairo --output ./artifacts/ZkPadAdmin.json --abi ./artifacts/ZkPadAdmin_abi.json
starknet-compile ./contracts/ZkPadLotteryToken.cairo --output ./artifacts/ZkPadLotteryToken.json --abi ./artifacts/ZkPadLotteryToken_abi.json
starknet-compile ./contracts/ZkPadIDOFactory.cairo --output ./artifacts/ZkPadIDOFactory.json --abi ./artifacts/ZkPadIDOFactory_abi.json
starknet-compile ./contracts/utils/xoroshiro128_starstar.cairo --output ./artifacts/xoroshiro128_starstar.json --abi ./artifacts/xoroshiro128_starstar_abi.json
printf "Contract compile successfully\n"

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare ZkPadStaking class"
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadStaking.json $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")

echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadVaultHarvestTask"
starknet declare --contract ../artifacts/ZkPadVaultHarvestTask.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadAdmin"
starknet declare --contract ../artifacts/ZkPadAdmin.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadToken"
starknet declare --contract ../artifacts/ZkPadToken.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadLotteryToken"
starknet declare --contract ../artifacts/ZkPadLotteryToken.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare ZkPadIDOFactory"
starknet declare --contract ../artifacts/ZkPadIDOFactory.json $STARKNET_DEVNET_ARGUMENTS

echo "Declare xoroshiro128_starstar"
starknet declare --contract ../artifacts/xoroshiro128_starstar.json $STARKNET_DEVNET_ARGUMENTS
printf "Declare successfully\n"

echo "Declare ZkPadIDO class"
ZK_PAD_IDO_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadIDOContract.json $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_IDO_DECLARATION_OUTPUT}"
ZK_PAD_IDO_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_IDO_DECLARATION_OUTPUT}")

################################################################################## DEPLOY ##########################################################################################
echo "Deploy ZkPadStaking"
starknet deploy --contract ../artifacts/ZkPadStaking.json --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS

echo "Deploy OZProxy"
ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/OZProxy.json --salt ${SALT} --inputs "${ZK_PAD_STAKING_CLASS_HASH}" $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}"
ZK_PAD_STAKING_PROXY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}")

echo "Deploy ZkPadVaultHarvestTask"
starknet deploy --contract ../artifacts/ZkPadVaultHarvestTask.json --inputs "${ZK_PAD_STAKING_PROXY_ADDRESS}" --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS

echo "Deploy ZkPadAdmin"
starknet deploy --contract ../artifacts/ZkPadAdmin.json --inputs "${NUMBER_OF_ADMINS}" ${ADMINS_ADDRESSES} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS

echo "Deploy ZkPadIDOFactory"
ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadIDOFactory.json --inputs "${ZK_PAD_IDO_CLASS_HASH}" ${OWNER_ADDRESS} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT}"
ZK_PAD_IDO_FACTORY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_IDO_FACTORY_DEPLOY_RECEIPT}")

echo "Deploy ZkPadLotteryToken"
ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadLotteryToken.json --inputs ${LOTTERY_URI_LEN} "${LOTTERY_URI_0}" "${LOTTERY_URI_1}" ${OWNER_ADDRESS} "${ZK_PAD_IDO_FACTORY_ADDRESS}" --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT}"
ZK_PAD_LOTTERY_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_LOTTERY_TOKEN_DEPLOY_RECEIPT}")

echo "Deploy xoroshiro128_starstar"
starknet deploy --contract ../artifacts/xoroshiro128_starstar.json --inputs "${XOROSHIRO_RNG_SEED}" --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS

echo "Deploy ZkPadToken"
ZK_PAD_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadToken.json --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS \
    --inputs ${ZKP_NAME} ${ZKP_SYMBOL} ${DECIMALS} ${INITIAL_SUPPLY} 0 ${RECIPIENT} ${OWNER_ADDRESS} ${MAX_SUPPLY} 0)
echo "${ZK_PAD_DEPLOYMENT_RECEIPT}"
ZKP_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_DEPLOYMENT_RECEIPT}")
printf "Deploy successfully\n"

echo "CONTRACTS DEPLOYMENT DONE 🚀"

################################################################################## INITIALIZE ##########################################################################################
CURRENT_BLOCK_NUMBER=$(starknet get_block $STARKNET_DEVNET_ARGUMENTS | jq '.block_number')
START_BLOCK=${CURRENT_BLOCK_NUMBER}
END_BLOCK=$((END_BLOCK=START_BLOCK + 1000))

echo "Initialize the vault"
starknet invoke --address "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function initializer \
    --inputs ${XZKP_NAME} ${XZKP_SYMBOL} "${ZKP_TOKEN_ADDRESS}" ${OWNER_ADDRESS} ${REWARD_PER_BLOCK} 0 "${START_BLOCK}" "${END_BLOCK}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS

sleep ${SLEEP}
echo "Initialize successfully"


echo "Set xZKP contract address for lottery token"
starknet invoke --address "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --abi ../artifacts/ZkPadLotteryToken_abi.json \
    --function set_xzkp_contract_address \
    --inputs "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS
sleep ${SLEEP}
echo "xZKP address set successfully"

echo "Set IDO factory address"
starknet invoke --address "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --abi ../artifacts/ZkPadLotteryToken_abi.json \
    --function set_ido_factory_address \
    --inputs "${ZK_PAD_IDO_FACTORY_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS
sleep ${SLEEP}
echo "IDO factory address set"

echo "Set lottery ticket contract address"
starknet invoke --address "${ZK_PAD_IDO_FACTORY_ADDRESS}" \
    --abi ../artifacts/ZkPadIDOFactory_abi.json \
    --function set_lottery_ticket_contract_address \
    --inputs "${ZK_PAD_LOTTERY_TOKEN_ADDRESS}" \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS

sleep ${SLEEP}
echo "Lottery ticket contract address set successfully"


echo "CONTRACTS SUCCESSFULLY INITIALIZED 🚀"
