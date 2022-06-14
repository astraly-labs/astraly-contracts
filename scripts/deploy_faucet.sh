#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
OWNER_ADDRESS=0x02356b628d108863Baf8644C945d97bAD70190aF5957031F4852D00D0f690a77
ZK_PAD_TOKEN_ADDRESS=0x042ad3518eceeecc43309cf7035ad83006d1b2abb9fb32ab0b79056b1d18c48b
WAIT_TIME=86400 # 1 DAY
WITHDRAWAL_AMOUNT=100000000000000000000 # 100 ZKP
FAUCET_AMOUNT=20000000000000000000000000 # 20M ZKP

SALT=0x1
MAX_FEE=54452800237082000

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
ZK_PAD_FAUCET_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadFaucet.json --inputs ${OWNER_ADDRESS} ${ZK_PAD_TOKEN_ADDRESS} ${WITHDRAWAL_AMOUNT} 0 ${WAIT_TIME} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
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

