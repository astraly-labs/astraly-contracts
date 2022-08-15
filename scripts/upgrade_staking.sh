#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner
# TODO: Use this only on devnet, otherwise comment next lines
# export STARKNET_GATEWAY_URL=http://127.0.0.1:5000
# export STARKNET_FEEDER_GATEWAY_URL=http://127.0.0.1:5000

SALT=0x4
MAX_FEE=54452800237082000

PROXY_ADDRESS=0x005ef67d8c38b82ba699f206bf0db59f1828087a710bad48cc4d51a2b0da4c29

################################################################################## COMPILE ##########################################################################################
cd ../
# mkdir -p artifacts
# echo "Compile contracts"
# starknet-compile ./contracts/AstralyStaking.cairo --output ./artifacts/AstralyStaking.json --abi ./artifacts/AstralyStaking_abi.json

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare AstralyStaking class"
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../build/AstralyStaking.json)
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")

################################################################################## DEPLOY ##########################################################################################
# echo "Deploy AstralyStaking"
# starknet deploy --contract ../artifacts/AstralyStaking.json --salt ${SALT}


echo "Upgrade Implementation"
starknet invoke --address "${PROXY_ADDRESS}" \
    --abi ../build/AstralyStaking_abi.json \
    --function upgrade \
    --inputs ${ZK_PAD_STAKING_CLASS_HASH} \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   
