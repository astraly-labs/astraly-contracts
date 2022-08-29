import os
from datetime import datetime, timedelta
from time import time 
from time import sleep
from dotenv import load_dotenv
from starknet_py.contract import Contract
from starknet_py.net.networks import TESTNET
from starknet_py.net.models import StarknetChainId
from starknet_py.net.gateway_client import GatewayClient
from starknet_py.net.networks import TESTNET, MAINNET
from starknet_py.net import AccountClient, KeyPair
from pymongo import MongoClient

import json
load_dotenv()

#Set address and key of moderator in .env file

moderator_address = os.getenv('MORDERATOR_ADDRESS')
moderator_private_key=os.getenv('MORDERATOR_PRIVATE_KEY')
moderator_public_key=os.getenv('MODERATOR_public_KEY')

lottery_contract_address = os.getenv('LOTTERY_CONTRACT_ADDRESS')

HOST = os.getenv("DB_HOST")

#list of accounts which activate the auto_burn option
auto_burn_accounts = []

#MUST SPECIFY THE IDO's ID:
IDO_ID = 0

# Creates an instance of the moderator account which is already deployed (testnet):

client = GatewayClient(TESTNET)
account_client_testnet = AccountClient(
    client=client,
    address= moderator_address,
    key_pair=KeyPair(private_key=moderator_private_key, public_key=moderator_public_key),
    chain=StarknetChainId.TESTNET,
)

mongo_client = MongoClient(HOST)
db = mongo_client['zkpad-dev']
history = db.questsHistory

#Get the lottery's contract abi

with open("./artifacts/abis/AstralyLotteryToken.json") as f:
    info_json = json.load(f)
lottery_abi = info_json

#Get the factory's contract abi

with open("./artifacts/abis/AstralyIDOFactory.json") as f:
    info_json = json.load(f)
factory_abi = info_json

#Get the IDO's contract abi

with open("./artifacts/abis/AstralyINOContract.json") as f:
    info_json = json.load(f)
INO_abi = info_json

#lottery contract address

lottery_contract_address = ("0x02d65855cfe2b0d6a8131cc811fb1333d830706539f1eaff4c292fcf4328dc27")

#IDO Factory Contract Address

factory_contract_address = ("0x0025fc12d7afb01f6ad82a793737b2c7908fc8d6fcd80bd55abf82eb38de9596")

#create the factory contract
factory_contract = Contract(
    factory_contract_address,
    factory_abi,
    account_client_testnet,
)

#create the lottery contract
lottery_contract = Contract(
    lottery_contract_address,
    lottery_abi,
    account_client_testnet,
)

#get the ido_contract_address

ido_address = hex(factory_contract.functions["get_ido_address"].call_sync(IDO_ID).address)

#create the ido contract

IDO_contract = Contract(
    ido_address,
    INO_abi,
    account_client_testnet,
)

#get the IDO contract registration start date

registration_start = IDO_contract.functions["get_registration"].call_sync().res['registration_time_starts']
now = datetime.today().timestamp()
time_until_registration_start = registration_start - now

#wait until the registration has started
if (time_until_registration_start > 0):
    sleep(registration_start - now)

#create a call list to integrate the multicall option
calls = []

#get the number of multicalls (depends on the number of transactions you want)
number_calls_per_multicall = 55
number_auto_burn_users = len(auto_burn_accounts)

#number of multicalls -1
number_multicalls = (number_auto_burn_users) // number_calls_per_multicall

iterator = 0
last_multicall_iterator = 0

#get the merkle_proof

merkle_proof = db.merkleProofs.find_one({"idoId":IDO_ID})

for address in auto_burn_accounts:
    iterator = iterator + 1
    print(iterator)

    #get the number of quests

    nb_Quest = history.count_documents({"address": address, "idoId": IDO_ID})

    #get the amount of tickets to burn per users

    amount = lottery_contract.functions["balanceOf"].call_sync(address, IDO_ID).balance

    #check if the amount is  greater than 0
    if amount>0:
        
    #add call to the calls list (function burn because no quest done)
        if (nb_Quest == 0):
            calls.append(lottery_contract.functions["burn"].prepare(address, IDO_ID, amount))

        if (nb_Quest > 0):
            calls.append(lottery_contract.functions["burn_with_quest"].prepare(address, IDO_ID, amount, nb_Quest, merkle_proof))

    #execute a multicall after iterator reachs the number_calls_per_multicall's value

        if ((number_multicalls > 0) and ((iterator % number_calls_per_multicall) == 0)):
            burn_tickets = account_client_testnet.execute_sync(calls=calls, max_fee=int(1e16))
            account_client_testnet.wait_for_tx_sync(burn_tickets.transaction_hash)
            print(burn_tickets)
            calls.clear()

    #last multicall
        if (iterator == number_auto_burn_users):
            burn_tickets = account_client_testnet.execute_sync(calls=calls, max_fee=int(1e16))
            account_client_testnet.wait_for_tx_sync(burn_tickets.transaction_hash)
            print(burn_tickets)





