export STARKNET_NETWORK=alpha-goerli
export SALT=0x1

## COMPILE
cd ../
echo "Compile contracts"
starknet-compile ./contracts/ZkPadStaking.cairo --output ./artifacts/ZkPadStaking.json --abi ./artifacts/ZkPadStaking_abi.json
starknet-compile ./contracts/openzeppelin/upgrades/OZProxy.cairo --output ./artifacts/OZProxy.json --abi ./artifacts/OZProxy_abi.json
echo "Contract compile successfully"


cd ./contracts
## DECLARE
echo "Declare ZkPadStaking class"
ZK_PAD_STAKING_DECLARATION_OUTPUT=$(starknet declare --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK})
echo "${ZK_PAD_STAKING_DECLARATION_OUTPUT}"
echo "Declare OZProxy class"
starknet declare --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK}

## DEPLOY
echo "Deploy ZkPadStaking"
starknet deploy --contract ../artifacts/ZkPadStaking.json --network ${STARKNET_NETWORK} --salt ${SALT}
echo "Deploy OZProxy"
starknet deploy --contract ../artifacts/OZProxy.json --network ${STARKNET_NETWORK} --salt ${SALT} --inputs "${ZK_PAD_STAKING_DECLARATION_OUTPUT##* }"

echo "Deploy successfully"
exit