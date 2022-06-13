#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
export OWNER_ACCOUNT_NAME=owner
SALT=0x1

OWNER_ADDRESS=0x01466fa1e3ba3d1fd6edd9b41d76d4c454104a6a38981e3807ab09befdd3af19

## COMPILE
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/ZkPadStaking.cairo --output ./artifacts/ZkPadStaking.json --abi ./artifacts/ZkPadStaking_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
starknet-compile ./contracts/ZkPadToken.cairo --output ./artifacts/ZkPadToken.json --abi ./artifacts/ZkPadToken_abi.json
printf "Contract compile successfully\n"

## DECLARE
echo "Declare ZkPadStaking class"
cd ./contracts

ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadStaking.json $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json $STARKNET_DEVNET_ARGUMENTS
echo "Declare ZkPadToken"
starknet declare --contract ../artifacts/ZkPadToken.json $STARKNET_DEVNET_ARGUMENTS
printf "Declare successfully\n"


## DEPLOY
echo "Deploy ZkPadStaking"
ZK_PAD_STAKING_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadStaking.json --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
ZK_PAD_STAKING_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_STAKING_DEPLOY_RECEIPT}")
echo "Deploy OZProxy"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")
ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/OZProxy.json --salt ${SALT} --inputs "${ZK_PAD_STAKING_CLASS_HASH}" $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}"
ZK_PAD_STAKING_PROXY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}")

echo "Deploy ZkPadToken"
ZKP_NAME=0x5a6b506164 # hex(str_to_felt("ZkPad"))
ZKP_SYMBOL=0x5a4b50 # hex(str_to_felt("ZKP"))
DECIMALS=18
INITIAL_SUPPLY=10000000000000000000000000
RECIPIENT=${OWNER_ADDRESS}
MAX_SUPPLY=100000000000000000000000000  # TODO: check value before deploy
ZK_PAD_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadToken.json --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS \
    --inputs ${ZKP_NAME} ${ZKP_SYMBOL} ${DECIMALS} ${INITIAL_SUPPLY} 0 ${RECIPIENT} ${OWNER_ADDRESS} ${MAX_SUPPLY} 0)
echo "${ZK_PAD_DEPLOYMENT_RECEIPT}"
ZKP_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_DEPLOYMENT_RECEIPT}")
printf "Deploy successfully\n"

CURRENT_BLOCK_NUMBER=$(starknet get_block $STARKNET_DEVNET_ARGUMENTS | jq '.block_number')

XZKP_NAME=0x785a6b506164 # hex(str_to_felt("xZkPad"))
XZKP_SYMBOL=0x785a4b50 # hex(str_to_felt("xZKP"))
REWARD_PER_BLOCK=10
START_BLOCK=${CURRENT_BLOCK_NUMBER}
END_BLOCK=$((END_BLOCK=START_BLOCK + 1000))

## INITIALIZE
echo "Initialize the vault"
starknet invoke --address "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function initializer \
    --inputs ${XZKP_NAME} ${XZKP_SYMBOL} "${ZKP_TOKEN_ADDRESS}" ${OWNER_ADDRESS} ${REWARD_PER_BLOCK} 0 "${START_BLOCK}" "${END_BLOCK}" \
    --max_fee 1 \
    --account ${OWNER_ACCOUNT_NAME} \
        $STARKNET_DEVNET_ARGUMENTS

echo "Initialize successfully"

exit