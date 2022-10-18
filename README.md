[![Tests](https://github.com/Astraly-Labs/astraly-contracts/actions/workflows/tests.yml/badge.svg)](https://github.com/Astraly-Labs/astraly-contracts/actions/workflows/tests.yml)
[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.gg/astralyxyz)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com/AstralyXYZ)

![banner](https://testnet.astraly.xyz/images/home/banner_3d_full.png)

# ☄️ Astraly Launch Smart Contracts

_Smart Contracts for Astraly Launch, Fundraising powered by on-chain reputation on Starknet. Learn more about it [here](https://wp.astraly.xyz)._

## Contracts

| Contract                                       | Title           | Description                                                            |
| ---------------------------------------------- | --------------- | ---------------------------------------------------------------------- |
| [AstralyIDO](./contracts/AstralyIDO.cairo)     | IDO Contract    | Handles the whole business logic of the IDO.                           |
| [AstralyINO](./contracts/AstralyINO.cairo)     | INO Contract    | Handles the whole business logic of the INO.                           |
| [AstralyIDOFactory](./AstralyIDOFactory.cairo) | IDO/INO Factory | Instanciates AstralyIDO/INO contracts for every new IDO/INO.           |
| [AstralyReferral](./AstralyReferral.cairo)     | Referral        | Handles the referral logic, one referral contract is deployed per IDO. |
| [Utils](./contracts/utils)                     | Cairo utils     |

# Development Workflow

This repository has been bootstrapped using [Nile](https://github.com/OpenZeppelin/nile) and [Poetry](https://python-poetry.org/docs/).

_Note: Mac and Mac M1 have special instructions you can refer to this [article](https://th0rgal.medium.com/the-easiest-way-to-setup-a-cairo-dev-environment-8f2a63610d46)_

1. Install Dependencies
   `poetry install`

2. Spin up a node (in a separate terminal window w/ the python environment running)
   `poetry run nile node`

3. Compile contracts
   `poetry run nile compile`

4. Run tests
   `poetry run pytest tests/`

These commands will test and deploy against your local node. If you want to deploy to the goerli testnet, use --network goerli instead.

# Contributing

We encourage pull requests.

1. **Create an [issue](https://github.com/Astraly-Labs/astraly-contracts/issues)** to describe the improvement/issue. Provide as much detail as possible in the beginning so the team understands your improvement/issue.
2. **Fork the repo** so you can make and test changes in your local repository.
3. **Test your changes** Make sure your tests (manual and/or automated) pass.
4. **Create a pull request** and describe the changes you made. Include a reference to the Issue you created.
5. **Monitor and respond to comments** made by the team around code standards and suggestions. Most pull requests will have some back and forth.

If you have further questions, visit [#technology in our discord](https://discord.gg/AstralyXYZ) and make sure to reference your issue number.

Thank you for taking the time to make our project better!
