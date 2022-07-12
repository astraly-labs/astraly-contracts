from utils import generate_merkle_proof, generate_merkle_root, get_leaves
from pymongo import MongoClient
import os
from pprint import pprint as pp
import sys
import json

sys.path.append(os.path.dirname(__file__))

# Get environment variables
HOST = os.getenv("DB_HOST")
NAME = os.getenv("DB_NAME")

IDO_ID = 3


def generateQuestData():
    client = MongoClient(HOST)
    db = client['zkpad-dev']
    accounts = db.accounts
    history = db.questsHistory
    recipients = []
    amounts = []
    print('Generating ...')
    for account in accounts.find():
        # pp(account)
        address = account['address']
        nb_Quest = history.count_documents(
            {"address": address, "idoId": IDO_ID})
        if nb_Quest > 0:
            recipients.append(int(address, 16))
            amounts.append(nb_Quest)
    MERKLE_INFO = get_leaves(recipients, amounts)
    leaves = list(map(lambda x: x[0], MERKLE_INFO))
    root = generate_merkle_root(leaves)
    print(root)
    cached_level = {}
    cached_level["1"] = []
    cached_level["2"] = []
    addressProofMap = dict(map(lambda x, i: [hex(x), generate_merkle_proof(
        leaves, i, cached_level)], recipients, [k for k in range(len(recipients))]))
    # merkle_proof = db.merkleProofs.find_one({"idoId":IDO_ID})
    # if merkle_proof :
    #     db.merkleProofs.find_one_and_update({})
    db.merkleProofs.insert_one({"idoId": IDO_ID, "data": addressProofMap})
    print("done")


generateQuestData()
