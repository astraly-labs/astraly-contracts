#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

# TODO: Use this only on devnet, otherwise comment next line
export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
SALT=0x1
MAX_FEE=1

ALPHA_ROAD_POOL=0x68f02f0573d85b5d54942eea4c1bf97c38ca0e3e34fe3c974d1a3feef6c33be
JEDI_SWAP_POOL=0x68f02f0573d85b2d54942eea4c1bf97c38ca0e3e34fe3c974d1a3feef6c33be
XZKP_ADDRESS= #TODO

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/AMMs/alpha_road/AlphaRoadWrapper.cairo --output ./artifacts/AlphaRoadWrapper.json --abi ./artifacts/AlphaRoadWrapper_abi.json
starknet-compile ./contracts/AMMs/jedi_swap/JediSwapWrapper.cairo --output ./artifacts/JediSwapWrapper.json --abi ./artifacts/JediSwapWrapper_abi.json

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare AlphaRoadWrapper"
starknet declare --contract ../artifacts/AlphaRoadWrapper.json $STARKNET_DEVNET_ARGUMENTS
echo "Declare JediSwapWrapper"
starknet declare --contract ../artifacts/JediSwapWrapper.json $STARKNET_DEVNET_ARGUMENTS

################################################################################## DEPLOY ##########################################################################################
echo "Deploy AlphaRoadWrapper"
ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/AlphaRoadWrapper.json --inputs ${ALPHA_ROAD_POOL} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT}"
ALPHA_ROAD_WRAPPER_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT}")

echo "Deploy JediSwapWrapper"
JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/JediSwapWrapper.json --inputs ${JEDI_SWAP_POOL} --salt ${SALT} $STARKNET_DEVNET_ARGUMENTS)
echo "${JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT}"
JEDI_SWAP_WRAPPER_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT}")



echo "Add AlphaRoad LP token as whitelisted token"
starknet invoke --address "${XZKP_ADDRESS}" \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function addWhitelistedToken \
    --inputs ${ALPHA_ROAD_POOL} "${ALPHA_ROAD_WRAPPER_ADDRESS}" 0 \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS

echo "Add Jedi Swap LP token as whitelisted token"
starknet invoke --address "${XZKP_ADDRESS}" \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function addWhitelistedToken \
    --inputs ${JEDI_SWAP_POOL} "${JEDI_SWAP_WRAPPER_ADDRESS}" 0 \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS

