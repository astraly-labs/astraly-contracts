# Deployment Scripts
---
## Configure
Prerequisitory: customize .env file to set wanted configuration. The `SIGNER` environment variable holds the primary key of the administrator.

Once you're happy with the values, export environement variables to make them available in subscripts:
```
set -a # automatically export all variables
source .env
set +a
```

---

## Deploy All
```
nile run scripts/deploy_all.py
```
---
## Run Transactions
```
nile run scripts/run_txs.py
```
---
## Update LP Whitelist
```
nile run scripts/update_whitelist.py
```
---
## Upgrade Staking Implementation
```
nile compile contracts/ZkPadStaking.cairo
nile run scripts/upgrade_staking.py
```
---