STARKNET_NETWORK=alpha-goerli
SALT=0x1
OWNER_ADDRESS=0x074bc1379968597de57a3629ce36f63d6b68894ded371d59e3d66f9d234a1df2

## COMPILE
cd ../
echo "Compile contracts"
starknet-compile ./contracts/ZkPadStaking.cairo --output ./artifacts/ZkPadStaking.json --abi ./artifacts/ZkPadStaking_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
starknet-compile ./contracts/ZkPadToken.cairo --output ./artifacts/ZkPadToken.json --abi ./artifacts/ZkPadToken_abi.json
printf "Contract compile successfully\n"

## DECLARE
echo "Declare ZkPadStaking class"
cd ./contracts
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK})
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK}
echo "Declare ZkPadToken"
starknet declare --contract ../artifacts/ZkPadToken.json --network ${STARKNET_NETWORK}
printf "Declare successfully\n"

## DEPLOY
echo "Deploy ZkPadStaking"
starknet deploy --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK} --salt ${SALT}
echo "Deploy OZProxy"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")
ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT=$(starknet deploy --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK} --salt ${SALT} --inputs "${ZK_PAD_STAKING_CLASS_HASH}")
echo "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}"
ZK_PAD_STAKING_PROXY_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_STAKING_PROXY_DEPLOY_RECEIPT}")

echo "Deploy ZkPadToken"
ZKP_NAME=0x5a6b506164 # hex(str_to_felt("ZkPad"))
ZKP_SYMBOL=0x5a4b50 # hex(str_to_felt("ZKP"))
DECIMALS=18
INITIAL_SUPPLY=10000000000000000000000000
RECIPIENT=${OWNER_ADDRESS}
MAX_SUPPLY=100000000000000000000000000  # TODO: check value before deploy
ZK_PAD_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/ZkPadToken.json --network ${STARKNET_NETWORK} --salt ${SALT} \
    --inputs ${ZKP_NAME} ${ZKP_SYMBOL} ${DECIMALS} ${INITIAL_SUPPLY} 0 ${RECIPIENT} ${OWNER_ADDRESS} ${MAX_SUPPLY} 0)
echo "${ZK_PAD_DEPLOYMENT_RECEIPT}"
ZKP_TOKEN_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ZK_PAD_DEPLOYMENT_RECEIPT}")
printf "Deploy successfully\n"

CURRENT_BLOCK_NUMBER=$(starknet get_block --network ${STARKNET_NETWORK} | jq '.block_number')

XZKP_NAME=0x785a6b506164 # hex(str_to_felt("xZkPad"))
XZKP_SYMBOL=0x785a4b50 # hex(str_to_felt("xZKP"))
REWARD_PER_BLOCK=10
START_BLOCK=${CURRENT_BLOCK_NUMBER}
END_BLOCK=$((END_BLOCK=START_BLOCK + 1000))

## INITIALIZE
echo "Initialize the vault"
starknet invoke --address "${ZK_PAD_STAKING_PROXY_ADDRESS}" \
    --network ${STARKNET_NETWORK} \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function initializer \
    --inputs ${XZKP_NAME} ${XZKP_SYMBOL} "${ZKP_TOKEN_ADDRESS}" ${OWNER_ADDRESS} ${REWARD_PER_BLOCK} 0 "${START_BLOCK}" "${END_BLOCK}" \
    --max_fee 1 \
    --wallet __default__

echo "Initialize successfully"

exit