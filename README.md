# Morpho AAVE V3

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

- Morpho Proxy:
- Morpho Implementation:
- PositionsManager:

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
- Create a `.env` according to the example file.

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
