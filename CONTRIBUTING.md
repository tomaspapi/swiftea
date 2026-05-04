# Contributing

Thanks for taking an interest in Swiftea.

Swiftea is intentionally small. Good contributions usually make the app more reliable, more native to macOS, or easier to maintain without expanding the product into a general Bluetooth dashboard.

## Development

Run the app:

```zsh
./script/build_and_run.sh
```

Run tests:

```zsh
swift test --scratch-path "${TMPDIR%/}/swiftea-swiftpm-build"
```

If you change Xcode project structure, update `project.yml` and regenerate `Swiftea.xcodeproj` with XcodeGen.

## Pull Requests

- Keep changes focused.
- Prefer native macOS controls and behaviors.
- Add or update tests when changing model, Bluetooth parsing, persistence, or notification behavior.
- Avoid adding network services, accounts, analytics, or cloud dependencies.
- For Bluetooth behavior changes, describe the device model, firmware if known, and manual validation performed.

## Project Scope

Swiftea is currently centered on Ember Mug 2. Support for other Ember devices should be treated as hardware-specific work and should be validated with real devices whenever possible.
