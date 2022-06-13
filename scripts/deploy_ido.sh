#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner

# TODO: Use this only on devnet, otherwise comment next line
export STARKNET_DEVNET_ARGUMENTS="--gateway_url http://127.0.0.1:5000 --feeder_gateway_url http://127.0.0.1:5000"
SALT=0x1

OWNER_ADDRESS=0xc45388638835815ffbee415184905349efdc167540105c2ab022361d5bfca5
IDO_TOKEN_PRICE=10000000000000000
IDO_TOKENS_TO_SELL=100000000000000000000000
# vestion portion percentages must add up to 1000
IDO_PORTION_VESTING_PRECISION=1000
# users can't burn more than 10000 lottery tickets
IDO_LOTTERY_TOKENS_BURN_CAP=10000
# Timestamp values
day=12312312312 # TODAY TIMESTAMP
timeDeltaDays=$((30 * 24 * 60 * 60))
timeDeltaWeeks=$((7 * 24 * 60 * 60))
IDO_SALE_END=$((day + timeDeltaDays))
REGISTRATION_END=$((day + (2 * 24 * 60 * 60)))
REGISTRATION_START=$((day + (1 * 24 * 60 * 60)))
IDO_TOKEN_UNLOCK=$(($IDO_SALE_END + $timeDeltaWeeks))
# VESTING_PERCENTAGES & VESTING_TIMES_UNLOCKED arrays must match in length
VESTING_PERCENTAGES = [100, 200, 300, 400]
VESTING_TIMES_UNLOCKED = [
    1 + (1 * 24 *
                                         60 * 60),  # 1 day after tokens unlock time
    # 8 days after tokens unlock time
    1 + (8 * 24 * 60 * 60),
    # 15 days after tokens unlock time
    1 + (15 * 24 * 60 * 60),
    # 22 days after tokens unlock time
    1 + (22 * 24 * 60 * 60)
]

ZK_PAD_FACTORY_ADDRESS=0x069bcaad4741a83821040ad395805c34d1d5e69f5eede024bbd6b6f5aac7bdbc

echo "Create IDO"
starknet invoke --address "${ZK_PAD_FACTORY_ADDRESS}" \
    --abi ../artifacts/ZkPadIDOFactory_abi.json \
    --function create_ido \
    --max_fee 1 \
    --account ${OWNER_ACCOUNT_NAME} \
    $STARKNET_DEVNET_ARGUMENTS

echo "IDO SUCCESSFULLY CREATED 🚀"
exit