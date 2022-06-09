STARKNET_NETWORK=alpha-goerli
SALT=0x1

## COMPILE
cd ../
echo "Compile contracts"
starknet-compile ./contracts/ZkPadStaking.cairo --output ./artifacts/ZkPadStaking.json --abi ./artifacts/ZkPadStaking_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
echo "Contract compile successfully"

## DECLARE
echo "Declare ZkPadStaking class"
cd ./contracts
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK})
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK}

## DEPLOY
echo "Deploy ZkPadStaking"
starknet deploy --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK} --salt ${SALT}
echo "Deploy OZProxy"
ZK_PAD_STAKING_CLASS_HASH=$(awk 'NR==2 {print $4}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")
starknet deploy --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK} --salt ${SALT} --inputs "${ZK_PAD_STAKING_CLASS_HASH}"
echo "Deploy successfully"

CURRENT_BLOCK_NUMBER=$(starknet get_block --network ${STARKNET_NETWORK} | jq '.block_number')

XZKP_NAME=0x785a6b506164 #str_to_felt("xZkPad")
XZKP_SYMBOL=0x785a4b50 # str_to_felt("xZKP")
ZKP_ADDRESS=0x1
OWNER_ADDRESS=0x69108f169548ff4eb3d8531bd0a1d647364d0ecdee8c7630ceaccb9632a25b9
REWARD_PER_BLOCK=10
START_BLOCK=${CURRENT_BLOCK_NUMBER}
END_BLOCK=$((END_BLOCK=${START_BLOCK} + 1000))

## INITIALIZE
echo "Initialize the vault"
ZK_PAD_STAKING_CONTRACT_ADDRESS=$(awk 'NR==3 {print $3}' <<< "${ZK_PAD_STAKING_DECLARATION_OUTPUT}")
starknet invoke --address "${ZK_PAD_STAKING_CONTRACT_ADDRESS}" \
    --network ${STARKNET_NETWORK} \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function initializer \
    --inputs ${XZKP_NAME} ${XZKP_SYMBOL} ${ZKP_ADDRESS} ${OWNER_ADDRESS} ${REWARD_PER_BLOCK} 0 "${START_BLOCK}" "${END_BLOCK}" \
    --max_fee 1 \
    --wallet __default__

echo "Initialize successfully"

exit