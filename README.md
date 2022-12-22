# morpho-aave-v3

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
