#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
OWNER_ADDRESS=0xc45388638835815ffbee415184905349efdc167540105c2ab022361d5bfca5
ZK_PAD_TOKEN_ADDRESS=0x1
WAIT_TIME=86400 # 1 DAY
WITHDRAWAL_AMOUNT=100000000000000000000 # 100 ZKP
FAUCET_AMOUNT=20000000000000000000000000 # 20M ZKP

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/ZkPadFaucet.cairo --output ./artifacts/ZkPadFaucet.json --abi ./artifacts/ZkPadFaucet_abi.json
printf "Contract compile successfully\n"

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare ZkPadFaucet class"
ZK_PAD_FAUCET_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadFaucet.json $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_FAUCET_DECLARATION_OUTPUT}"
ZK_PAD_FAUCET_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_FAUCET_DECLARATION_OUTPUT}")

################################################################################## DEPLOY ##########################################################################################
echo "Deploy ZkPadFaucet"
ZK_PAD_FAUCET_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadFaucet.json --salt ${SALT} --inputs ${OWNER_ADDRESS} ${ZK_PAD_TOKEN_ADDRESS} ${WITHDRAWAL_AMOUNT} 0 ${WAIT_TIME} $STARKNET_DEVNET_ARGUMENTS)
echo "${ZK_PAD_FAUCET_DEPLOY_RECEIPT}"
ZK_PAD_FAUCET_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_FAUCET_DEPLOY_RECEIPT}")

echo "Mint zkp to the faucet"
starknet invoke --address "${ZK_PAD_TOKEN_ADDRESS}" \
    --abi ../artifacts/ZkPadToken.json \
    --function mint \
    --inputs "${ZK_PAD_FAUCET_ADDRESS}" ${FAUCET_AMOUNT} 0\
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS
echo "Mint successfully"

