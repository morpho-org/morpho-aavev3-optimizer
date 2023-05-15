# Morpho-AaveV3

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://i.imgur.com/uLq5V14.png">
  <img alt="" src="https://i.imgur.com/ZiL1Lr2.png">
</picture>

---

## What is Morpho?

Morpho is a lending pool optimizer: it improves the capital efficiency of positions on existing lending pools by seamlessly matching users peer-to-peer.

- Morpho's rates stay between the supply rate and the borrow rate of the pool, reducing the interests paid by the borrowers while increasing the interests earned by the suppliers. It means that you are getting boosted peer-to-peer rates or, in the worst case scenario, the APY of the pool.
- Morpho also preserves the same experience, the same liquidity and the same parameters (collateral factors, oracles, …) as the underlying pool.

TL;DR: Instead of borrowing or lending on your favorite AaveV3 pool, you would be better off using Morpho-AaveV3.

---

## Contracts overview

The Morpho protocol is designed at its core with the main Morpho contract delegating calls to the PositionsManager implementation contract (to overcome the contract size limit).

The main user's entry points are exposed in the [`Morpho`](./src/Morpho.sol) contract. It inherits from [`MorphoGetters`](./src/MorphoGetters.sol) which contains all the functions used to query Morpho-AaveV3, [`MorphoSetters`](./src/MorphoSetters.sol) which contains all the functions used by the governance to manage the protocol, [`MorphoInternal`](./src/MorphoInternal.sol), and [`MorphoStorage`](./src/MorphoStorage.sol), where the protocol's internal logic & storage is located. This contract delegates call to the [`PositionsManager`](./src/PositionsManager.sol), that has the exact same storage layout: this contracts inherits from [`PositionsManagerInternal`](./src/PositionsManagerInternal.sol) which contains all the internal accounting logic and in turn inherits from [`MatchingEngine`](./src/MatchingEngine.sol), which contains the matching engine internal functions.

It also interacts with [`RewardsManager`](./src/RewardsManager.sol), which manages AaveV3's rewards if any.

---

## Documentation

- [White Paper](https://whitepaper.morpho.xyz)
- [Yellow Paper](https://yellowpaper.morpho.xyz/)
- [Morpho Documentation](https://docs.morpho.xyz)
- [Morpho Developers Documentation](https://developers.morpho.xyz)

---

## Audits

All audits are stored in the [audits](./audits/)' folder.

---

## Bug bounty

A bug bounty is open on Immunefi. The rewards and scope are defined [here](https://immunefi.com/bounty/morpho/).
You can also send an email to [security@morpho.xyz](mailto:security@morpho.xyz) if you find something worrying.

---

## Deployment Addresses

### Morpho-Aave-V3 (Ethereum)

- Morpho Proxy: [0x33333aea097c193e66081e930c33020272b33333](https://etherscan.io/address/0x33333aea097c193e66081e930c33020272b33333)
- Morpho Implementation: [0xcb5309bdda3463ece2d020c9d0564a95c5a90b53](https://etherscan.io/address/0xcb5309bdda3463ece2d020c9d0564a95c5a90b53)
- PositionsManager: [0x4592e45e0c5DbEe94a135720cCfF2e4353dAc6De](https://etherscan.io/address/0x4592e45e0c5DbEe94a135720cCfF2e4353dAc6De)

### Common (Ethereum)

- ProxyAdmin: [0x99917ca0426fbc677e84f873fb0b726bb4799cd8](https://etherscan.io/address/0x99917ca0426fbc677e84f873fb0b726bb4799cd8)

---

## Importing contracts

Using forge:

```bash
forge install morpho-dao/morpho-aave-v3
```

---

## Development

### Getting Started

- Install [Foundry](https://github.com/foundry-rs/foundry).
- Run `make install` to initialize the repository.
- Create a `.env` file according to the [`.env.example`](./.env.example) file.

### Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a fork of real networks, which allows us to interact directly with liquidity pools of AaveV3. Note that you need to have an RPC provider that have access to Ethereum or Avalanche.

For testing, make sure `foundry` is installed and install dependencies (git submodules) with:

```bash
make install
```

To run tests on different protocols, navigate a Unix terminal to the root folder of the project and run the command of your choice:

To run the whole test suite:

```bash
make test
```

or to run only tests matching an input:

```bash
make test-Borrow
```

or to run only unit, internal, integration or invariant tests:

```bash
make test-[unit/internal/integration/invariant]
```

For the other commands, check the [Makefile](./Makefile).

### VSCode setup

Configure your VSCode to automatically format a file on save, using `forge fmt`:

- Install [emeraldwalk.runonsave](https://marketplace.visualstudio.com/items?itemName=emeraldwalk.RunOnSave)
- Update your `settings.json`:

```json
{
  "[solidity]": {
    "editor.formatOnSave": false
  },
  "emeraldwalk.runonsave": {
    "commands": [
      {
        "match": ".sol",
        "isAsync": true,
        "cmd": "forge fmt ${file}"
      }
    ]
  }
}
```

---

## Test coverage

Test coverage is reported using [foundry](https://github.com/foundry-rs/foundry) coverage with [lcov](https://github.com/linux-test-project/lcov) report formatting (and optionally, [genhtml](https://manpages.ubuntu.com/manpages/xenial/man1/genhtml.1.html) transformer).

To generate the `lcov` report, run:

```bash
make coverage
```

The report is then usable either:

- via [Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) following [this tutorial](https://mirror.xyz/devanon.eth/RrDvKPnlD-pmpuW7hQeR5wWdVjklrpOgPCOA-PJkWFU)
- via html, using `make lcov-html` to transform the report and opening `coverage/index.html`

---

## Storage seatbelt

[foundry-storage-check](https://github.com/Rubilmax/foundry-storage-diff) is currently running on every PR to check that the changes introduced are not modifying the storage layout of proxied smart contracts in an unsafe way.

---

## Questions & Feedback

For any question or feedback you can send an email to [merlin@morpho.xyz](mailto:merlin@morpho.xyz).

---

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).
