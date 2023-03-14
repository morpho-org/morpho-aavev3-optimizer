# Morpho AAVE V3

## Getting Started

- Install [Foundry](https://github.com/foundry-rs/foundry).
- Run `make install` to initialize the repository.
- Create a `.env` according to the example file.

## Development

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
            },
        ]
    }
}
```

## Testing

View the Makefile to see testing commands. For example, running `make test-unit` will run the unit tests.

## Documentation

## Audits

## Deployments & Upgrades

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).