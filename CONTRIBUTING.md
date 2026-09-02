# Contributing to Swiftea

Swiftea is a personal, maintainer-led project. Bug reports and suggestions are welcome, but external code contributions and pull requests are not accepted.

## Report a bug

Use the repository’s bug report form. Include the Swiftea version, macOS version, mug model when relevant, expected behavior, and observed behavior. Do not post full serial numbers, private logs, or sensitive local paths.

## Suggest an improvement

Use the feature request form to describe the problem or workflow first, followed by the behavior you would find useful. Suggestions may inform the roadmap, but submitting one does not promise implementation.

## Security reports

Follow the [Security Policy](SECURITY.md). Do not disclose a suspected vulnerability in a public issue.

## Code and forks

The Swiftea repository does not accept external code contributions or pull requests. Swiftea’s source code is released under the highly permissive Zero-Clause BSD (0BSD) License, so you are welcome to fork it, modify it, and use it for any purpose permitted by the license.

## Supported hardware

Swiftea is developed and tested with Ember Mug 2, the only model currently supported. Other Ember products have not been validated and should be treated as unsupported, even if Swiftea happens to detect them.

## Build and test

Run the app with `./script/build_and_run.sh` and run tests with `swift test --scratch-path "${TMPDIR%/}/swiftea-swiftpm-build"`.
